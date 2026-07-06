---
name: implement-from-issue
description: 採択済み GitHub Issue をもとに実装・単体テスト・静的解析・PR 作成・Issue ステータス更新まで一気通貫で自動化するときに使う。製造フェーズ向け。E2E は実行しない（AWS 環境構築後に E2E リポジトリの別工程）。
context: fork
argument-hint: <ISSUE-NUMBER>
---

# GitHub Issue から実装・品質チェック・PR 作成を行う

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

この skill はメインセッションから使う（fork しない）。

対象 Issue: $ARGUMENTS

## 前提条件

- GitHub Issue が「採択済み」状態（例: ラベル `status:ready` が付与されている）であること
- 設計フェーズが採択済みであること（**採択＝docs リポジトリの `main` へのマージ**。Issue はマージ契機で採択済み設計書から自動起票されるため CI では自明。ローカルでは対象設計書が docs の `main` にマージ済みかを確認し、未マージなら中断）
- `gh` CLI がインストール・認証済みであること（`GH_TOKEN` 環境変数。`gh auth status` で確認）
- `git` が利用可能で、リモート `origin` が GitHub に設定済みであること
- PAT は classic（`repo` + `project`、Organization 所有 Project なら `read:org`）。`GH_TOKEN` は docker-compose が `GITHUB_PERSONAL_ACCESS_TOKEN` からマッピング済み
- リモートの `main` / `master` / `develop` には **Branch protection rules** が設定されており、PR 経由でしかマージできない状態であること

## 手順

### 1. Issue 情報の取得

1. `gh issue view $ARGUMENTS --json number,title,body,labels,assignees,url` で Issue を取得する
2. 以下を展開して内部メモに整理する
   - Title / Body / 受け入れ条件 / 付与ラベル（`type:*`）/ Assignee
   - 関連する設計書ファイルパス（Body に記載されていれば参照）
   - 関連する画面 ID（SCR-XXX）と関連業務ルール（BR-XXX）
3. `gh issue view $ARGUMENTS --json comments` でコメント一覧を取得し、以下のルールで処理する
   - コメント本文を前後の空白・改行除去後に `@claude` と一致するコメントは**処理対象外**とする（起動トリガーのみで内容を持たない）
   - 残ったコメントを時系列順に読み、Issue 本文を補完する追加仕様・修正指示・背景情報を内部メモに追記する

<!-- rules 改善（S5）: 依存 Issue クローズ確認ゲート -->
#### 1.1. 依存 Issue クローズ確認ゲート（S5・必須）

Issue 本文に `Depends on: #XX`（依存 Issue）の記載があれば、各依存 Issue の状態を確認する。DB→BE API→FE 画面 の順序事故（型定義・API 不在で画面が組めない等）を予防するためのハードゲート。

```bash
# Issue 本文から "Depends on: #NN" を抽出し、各依存 Issue の state を確認
gh issue view $ARGUMENTS --json body -q .body | grep -Eo 'Depends on:[^\n]*' || true
gh issue view <依存Issue番号> --json number,state -q '.number,.state'
```

- 依存 Issue のいずれかが `OPEN`（未クローズ）の場合は **実装を開始せず中断**し、「依存 Issue #XX が未クローズのため着手不可。先に #XX をマージしてください」と報告する。
- 依存記載が無い場合はそのまま次へ進む。

<!-- rules 改善（S7）: Issue 規模の事前評価（コンテキスト溢れ対策） -->
#### 1.2. Issue 規模の事前評価（S7・コンテキスト溢れ対策）

設計書・Issue 本文から**変更ファイル数を見積もる**（新規画面コンポーネント / カスタムフック / store / API クライアント / 型定義 / テストの概算）。

- 見積もりが **30 ファイル超**の場合は、実装に着手せず **分割 ESCALATE**: 「規模過大（推定 NN ファイル）。画面単位・機能単位に Issue を分割してから再実行してください」と報告して中断する。
- 30 以下なら次へ進む。各レイヤ（画面/フック/サービス）完了時に中間サマリを書き出す（手順4参照）。

### 2. 要件定義・設計書の確認

- `docs/requirements/` 配下から関連要件を読む
  - Issue 内の SCR-XXX / 機能名から `docs/requirements/functional/[機能名].md` 等を特定する
- `docs/design/` 配下から関連設計書を読む
  - 画面 Issue（`type:screen`）: `docs/design/screens/[scr-id]-*.md` と関連 `docs/design/api/*.yaml`
  - API Issue（`type:api`）: `docs/design/api/[リソース名].yaml`（1 ファイルに同リソースの全 HTTP メソッドが集約されているため、1 Issue で全メソッドの実装を扱う。共通参照は `docs/design/api/_common.yaml`）
  - DB Issue（`type:table`）: `docs/design/tables/[テーブル名].md` と全体方針の `docs/design/DB定義.md`
<!-- rules 改善（A-2）: 横断設計書の必読（共通部品の再発明防止） -->
- **横断設計書を必ず読む（A-2 対策・必読）**: 種別を問わず `docs/design/共通部品設計.md`・`docs/design/フロントエンド共通設計.md`（共通 API クライアント `apiClient.ts` / 共通エラーハンドリング / 共通バリデーション / 共通レイアウト / 認可制御 等）と `docs/design/セキュリティ設計.md`（認可・ルーティング認可制御 3 層・JWT 取り扱い）を読み、**定義済みの共通部品を再実装せず再利用する**。再発明は `review-implementation` の `common_component` で BLOCK となる。FE 実装規約の正典は対象 repo の `.claude/rules/frontend-*.md` であり、矛盾時は frontend ルールを正とする。Issue 本文の「横断設計（必読）」セクションも参照する。
- 要件定義または設計書が存在しない場合はユーザーに確認を取り、作業を中断する

<!-- rules 改善（RC-07 / RC-06）: プロジェクト初期化・品質 config・新規依存の実在性チェック -->
### 2.5. プロジェクト初期化チェック（ビルド定義の存在確認）

実装対象リポジトリの**ビルド定義**（`package.json`）が存在するか確認する。存在しない場合は実装を開始せず中断し、事前配置を依頼する。品質 config 群の実在・参照照合（RC-07/D-21）と新規依存の確定表照合・実在性確認（RC-06/D-14）を含む詳細手順は [references/project-init-check.md](references/project-init-check.md) を参照し、適用必須とする。

存在確認・config 照合・依存確認のいずれかで NG の場合は中断して事前配置・確定を依頼し、すべて満たしてから手順3へ進む（`npm run ...` 等が通る前提とし、設定の即興生成はしない）。

### 3. ブランチの作成

```bash
git checkout main
git pull --rebase origin main
git checkout -b feature/issue-$ARGUMENTS
```

ブランチ名規約: `feature/issue-<ISSUE-NUMBER>`

`main` / `master` / `develop` への直接 push は deny ルールおよび Branch protection で禁止されている。

### 3.5 テスト設計の先行起動（draft モード）

実装と並行して `/test-design-from-issue` の `draft` モードを起動し、設計書から TC-XXX・単体テストマトリクスを先出しする（Pattern 2 独立並列）。実コードとの突合は `finalize` モードで行うため、コードが無くても実行できる。

```
/test-design-from-issue $ARGUMENTS draft
```

完了後に `docs/test/単体テストマトリクス.md` が作成されていることを確認する。未整合セルは「要整合（実装後）」と明記されているのが正常。

### 4. 実装（単一セッション・Agent Teams 不使用）

> 本プロジェクトは Agent Teams（experimental の teammate 機能）を使用しない。並列実行は Pattern 2（Parallel Fan-Out）で代替する。実装はこの単一セッション内で設計書に従って進める。

実装前に既存コードを Glob / Grep で調査し、変更影響範囲を特定する。次の順序で進め、同じ Entity / migration に触れる作業を同時に走らせない（依存方向 DB → バックエンド → フロントエンドに沿う）。

1. **DB**: migration ファイル / Entity マッピング
   - 入力: `docs/design/tables/[テーブル名].md` と `docs/design/DB定義.md`
2. **バックエンド**: Controller / Service / Repository / Validation / 例外ハンドリング
   - 入力: `docs/design/api/[リソース名].yaml`（共通スキーマは `docs/design/api/_common.yaml`）
   - Controller は薄く保ち、業務ロジックは Service、永続化は Repository に寄せる（CLAUDE.md の設計原則）
3. **フロントエンド**: React 画面 / ルーティング / コンポーネント / 状態管理 / API クライアント / フォームバリデーション
   - 入力: `docs/design/screens/[scr-id]-*.md` と `docs/design/api/*.yaml`

   - **3a. 型定義の事前確認と生成（必須）** / **3b. API 呼び出しは `createApiClient` 使用（必須）**: 詳細手順は [references/api-client-guide.md](references/api-client-guide.md) を参照。
   - 表示は Presentational / Container に分け、API 呼び出しは `src/features/*/services/` に集約する

各レイヤー完了ごとに最も狭い検証（コンパイル / 型チェック）を回してから次へ進む。

<!-- rules 改善: references へ外出し -->
画面 / フック / サービス（API クライアント）の各まとまり完了時に、次のまとまりが参照すべき確定情報を**中間サマリファイル**（own リポジトリ直下 `.skills-state/implement/impl-summary-$ARGUMENTS.md`・gitignore 対象）に追記する。長い実装でコンテキストが溢れても、後続はこのファイルを Read して整合を取れる。記載項目・追記コマンド例は [references/layer-implementation-detail.md](references/layer-implementation-detail.md) を参照し、適用必須とする（S7・コンテキスト溢れ対策）。

### 5. 品質ゲート（Pattern 2 並列ファンアウト）

実装完了後、次の 3 つの独立した品質チェックを **並列**（Pattern 2 Parallel Fan-Out）で実行する。各チェックは対応する補助 skill の手順に従う。Agent Teams は使わず、互いに独立したチェックの同時実行として並列化する。

<!-- rules 改善: references へ外出し -->
品質ゲート一覧表（単体テスト+カバレッジ/ESLint/Prettier/npm audit/セキュリティレビュー）・コマンド・レポート出力パス、および **コード内容ハッシュのサイドカー出力（RC-07）** の詳細は [references/quality-gates.md](references/quality-gates.md) を参照し、適用必須とする。

- **E2E は本スキルでは実行しない**（AWS 環境構築後に E2E リポジトリの別工程として実施。`/e2e-from-design` は凍結中で呼び出さない）。
- **IT（結合テスト）はフロントエンドには存在しない**。MSW を使った API モック結合は単体テスト（TC-XXX）として扱う。
- カバレッジが閾値（分岐 90% / 命令 100%）に届かない場合は `/coverage-to-100` の手順で不足分を補う。
- すべてのゲートが成功するまで次のステップへ進まない。
- 失敗時は原因（アプリ側 / テスト側 / 環境）を切り分けて修正し、同じゲートを再実行する。新しい teammate は起動しない。
- 変更が非機能要件（性能・負荷・可用性）に関わる場合は `docs/design/非機能テスト計画.md` の該当検証を実施し結果を記録する。実装した AC-XXX とテスト ID（TC/E2E）の対応は `docs/test/トレーサビリティマトリクス.md`（RTM）に反映する。

### 5.5 テスト設計の確定（finalize モード）

実装と全品質ゲートが通過したことを確認してから `/test-design-from-issue` の `finalize` モードを実行する。テストコードと TC-XXX の件数・シナリオを突合し、RTM に反映する。ハードゲート（`check-test-matrix.sh`）が exit 0 を返すまで完了しない。

```
/test-design-from-issue $ARGUMENTS finalize
```

ゲート通過後、`docs/test/` 配下のマトリクスが feature ブランチへ commit/push され PR に含まれる（`/test-design-from-issue` が行う）。

### 6. コミットと push

```bash
git add <変更ファイルを個別に指定>
git commit -m "feat(#$ARGUMENTS): <Issue タイトル>

<実装内容の日本語サマリ>

Refs: #$ARGUMENTS"
git push -u origin feature/issue-$ARGUMENTS
```

- `main` への直接 push は禁止
- `git add -A` は使わず、変更ファイルを個別に指定する

### 7. Pull Request 作成

`gh pr create --base main --head feature/issue-$ARGUMENTS --title "feat(#$ARGUMENTS): <Issue タイトル>" --body-file <一時ファイル>` で PR を作成する。本文テンプレートは [references/pr-template.md](references/pr-template.md) を使う。

### 8. Issue ステータスの更新

`gh issue comment $ARGUMENTS --body "<レビュー依頼コメント>"` を追記し、
`gh issue edit $ARGUMENTS --remove-label status:ready --add-label status:in-review` でラベルを更新する。

### 9. 最終報告

以下を Markdown テーブルで報告する。

報告する Markdown テーブルの列構成は [references/pr-template.md](references/pr-template.md) の「最終報告テーブル」を参照する（適用必須）。

その後、人手レビューが必要であることを明記する。

## 完了条件

- Issue 情報・関連要件定義・関連設計書が確認されている
- feature ブランチが作成されている
- 要件定義の受け入れ条件と設計書に従って実装が完了している
- 単体テスト（Vitest）・ESLint・Prettier・npm audit（critical/high 0件）・セキュリティレビューがすべて通過している（E2E は対象外・別工程。IT 層はフロントエンドに存在しない）
- テスト設計マトリクス（TC-XXX）と RTM が `docs/test/` に出力され PR に含まれている（`check-test-matrix.sh` exit 0 確認済み）
- PR が作成され、Body に `Closes #$ARGUMENTS` が含まれている
- Issue ラベルが `status:in-review` に更新されている
- 後続の人手レビューが未実施であることが明記されている

## 注意事項

- 品質チェックで 1 つでも失敗した場合は push / PR 作成を行わない
- 大きな変更が発生する場合（ファイル数 > 30 等）は事前にユーザーへ確認する
- 認証情報は環境変数から参照し、リポジトリにコミットしない
- `.github/workflows/**` の編集は deny ポリシーで禁止されているため、CI 変更が必要な場合は別 Issue として人手で起票・レビューを通すこと。
