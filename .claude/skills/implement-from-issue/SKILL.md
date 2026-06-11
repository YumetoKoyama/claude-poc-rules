---
name: implement-from-issue
description: 採択済み GitHub Issue をもとに実装・単体テスト・静的解析・PR 作成・Issue ステータス更新まで一気通貫で自動化するときに使う。製造フェーズ向け。E2E は実行しない（AWS 環境構築後に E2E リポジトリの別工程）。
context: fork
argument-hint: <ISSUE-NUMBER>
---

# GitHub Issue から実装・品質チェック・PR 作成を行う

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/` は **docs リポジトリ（claude-poc-docs）ルート相対**の**読み取り入力**。製造フェーズの出力（テストマトリクス・RTM・レビュー結果）は **own リポジトリの `docs/test/`** に書き PR に含める（docs リポジトリには書かない）。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: docs 読み取りパスに `claude-poc-docs/` を前置する。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

入力（Issue）と出力（コード・テスト・PR）がファイル経由のため `context: fork` で実行する。`/implement-loop` の **produce 段**を担う（review は `/review-implementation` が担当）。

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

### 2. 要件定義・設計書の確認

- `docs/requirements/` 配下から関連要件を読む
  - Issue 内の SCR-XXX / 機能名から `docs/requirements/functional/[機能名].md` 等を特定する
- `docs/design/` 配下から関連設計書を読む
  - 画面 Issue（`type:screen`）: `docs/design/screens/[scr-id]-*.md` と関連 `docs/design/api/*.yaml`
  - API Issue（`type:api`）: `docs/design/api/[リソース名].yaml`（1 ファイルに同リソースの全 HTTP メソッドが集約されているため、1 Issue で全メソッドの実装を扱う。共通参照は `docs/design/api/_common.yaml`）
  - DB Issue（`type:table`）: `docs/design/tables/[テーブル名].md` と全体方針の `docs/design/DB定義.md`
- 要件定義または設計書が存在しない場合はユーザーに確認を取り、作業を中断する

### 2.5. プロジェクト初期化チェック（ビルド定義の存在確認・全リポ共通）

実装対象リポジトリの**ビルド定義**が存在するか確認する（Java 系＝`pom.xml` / Node 系＝`package.json`。リポジトリ種別に応じてどちらかが存在すべき）。

```bash
ls pom.xml package.json 2>/dev/null || echo "MISSING"
```

そのリポジトリに該当するビルド定義（Java は `pom.xml`、Node は `package.json`）と静的解析設定（`config/` 等）が**存在しない**場合は **実装を開始せず中断し、事前配置を依頼する**:

> ビルド定義（`pom.xml` または `package.json`）／静的解析設定が見つかりません。設定一式の事前配置が必要です。対象リポジトリのルートに配置してから再実行してください。

存在する場合はそのまま手順3へ進む（`mvn verify` / `npm run ...` 等が通る前提とし、設定の即興生成はしない）。

### 3. ブランチの作成

```bash
git checkout main
git pull --rebase origin main
git checkout -b feature/issue-$ARGUMENTS
```

ブランチ名規約: `feature/issue-<ISSUE-NUMBER>`

`main` / `master` / `develop` への直接 push は deny ルールおよび Branch protection で禁止されている。

### 3.5. テスト設計ドラフト（実装と並行・設計由来）

実装（手順4）と **並行** して、テスト設計のドラフトを先出しする。入力は設計書（AC-XXX・実装内容項目）であり実装コードに依存しないため、ここで前倒しできる（Pattern 2 の独立性。テストファースト的に実装の指針にもなる）。

```bash
/test-design-from-issue $ARGUMENTS draft
```

- `docs/test/` に 単体マトリクス・RTM のドラフトを起こし、TC-XXX と区分（正常系 / 異常系 / 境界値 / 権限境界）を AC（または実装内容項目）から先に決める（**結合テストは別工程**のため対象外）。
- この時点では実コードとの突合・ハードゲートは行わない。未確定セルは「要整合（実装後）」と明記し、確定は手順5.5 で行う。
- AC-XXX が無い共通基盤 Issue でも省略しない（設計書「実装内容」項目を観点化）。

### 4. 実装（単一セッション・Agent Teams 不使用）

> 本プロジェクトは Agent Teams（experimental の teammate 機能）を使用しない（設計方針: [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) §1・§8）。実装はこの単一セッション内で設計書に従って進める。

実装前に既存コードを Glob / Grep で調査し、変更影響範囲を特定する。次の順序で進め、同じ Entity / migration に触れる作業を同時に走らせない（依存方向 DB → バックエンド → フロントエンドに沿う）。

1. **DB**: migration ファイル / Entity マッピング
   - 入力: `docs/design/tables/[テーブル名].md` と `docs/design/DB定義.md`
2. **バックエンド**: Controller / Service / Repository / Validation / 例外ハンドリング
   - 入力: `docs/design/api/[リソース名].yaml`（共通スキーマは `docs/design/api/_common.yaml`）
   - Controller は薄く保ち、業務ロジックは Service、永続化は Repository に寄せる（CLAUDE.md の設計原則）
3. **フロントエンド**: React 画面 / ルーティング / コンポーネント / 状態管理 / API クライアント / フォームバリデーション
   - 入力: `docs/design/screens/[scr-id]-*.md` と `docs/design/api/*.yaml`
   - 表示は Presentational / Container に分け、API 呼び出しは `src/api/` に集約する

各レイヤー完了ごとに最も狭い検証（コンパイル / 型チェック）を回してから次へ進む。

### 5. 品質ゲート（Pattern 2 並列ファンアウト）

実装完了後、次の 3 つの独立した品質チェックを **並列**（Pattern 2 Parallel Fan-Out）で実行する。各チェックは対応する補助 skill の手順に従う。Agent Teams は使わず、互いに独立したチェックの同時実行として並列化する。

| 品質ゲート | 内容 | 参照する補助 skill |
| --- | --- | --- |
| 単体テスト | バックエンド: JUnit5 + Mockito + MockMvc / フロントエンド: Vitest（または Jest）+ React Testing Library（カバレッジ閾値は各確定表: BE `backend-00-stack.md` #13 = 命令100%/分岐90%・FE `frontend-00-stack.md` #10 = 100%、いずれも除外後） | `/unit-test-from-design` |
| 静的解析 | バックエンド: SpotBugs / Checkstyle / PMD / フロントエンド: ESLint / Prettier / TypeScript 型チェック | `/static-analysis-remediation` |
| セキュリティレビュー | OWASP ベースの自己点検（認可バイパス・IDOR/テナント越境・JWT 検証・機密情報のログ/レスポンス出力・入力サニタイズ）。PR 作成前に必須 | `docs/design/セキュリティテスト観点.md` |

- **E2E は本スキルでは実行しない**（AWS 環境構築後に E2E リポジトリの別工程として実施。`/e2e-from-design` は凍結中で呼び出さない）。
- **結合テスト（IT-XXX）も本スキルでは設計・実施しない**。結合テストはフィーチャ単位で複数 Issue をまたぐため、設計・実施とも **結合テスト工程**（`/integration-test-from-design`）で行う（E2E と同様の切り分け）。
- カバレッジが確定表の閾値（BE #13 命令100%/分岐90% ・ FE #10 100%、いずれも除外後）に届かない場合は `/coverage-to-100` の手順で不足分を補う。
- すべてのゲートが成功するまで次のステップへ進まない。
- 失敗時は原因（アプリ側 / テスト側 / 環境）を切り分けて修正し、同じゲートを再実行する。新しい teammate は起動しない。
- 変更が非機能要件（性能・負荷・可用性）に関わる場合は `docs/design/非機能テスト計画.md` の該当検証を実施し結果を記録する。実装した AC-XXX と **TC-XXX** の対応は own リポジトリの `docs/test/トレーサビリティマトリクス.md`（RTM）に反映する（IT/E2E 列は各別工程が記入）。

#### 品質ゲートのレポート出力パス（固定）

後段の `review-implementation` がレポートの **更新時刻**で「品質ゲートが実際に実行されたか」を判定できるよう、各ゲートは次の固定パスにレポートを出力する。

| ゲート | 出力パス |
| --- | --- |
| バックエンド単体テスト | `target/surefire-reports/` |
| バックエンドカバレッジ（JaCoCo） | `target/site/jacoco/jacoco.xml` |
| バックエンド静的解析 | `target/`（SpotBugs / Checkstyle / PMD の各レポート） |
| フロントエンド単体テスト + カバレッジ | `coverage/`（Istanbul） |
| フロントエンド静的解析 | `eslint-report.json`（ESLint）/ 型チェックは実行ログ |

> 上表は own リポジトリのルートを起点とする（CI は子リポジトリ単体チェックアウトのため `backend/` `frontend/` の接頭辞は付かない）。モジュール構成が異なる場合は実際のモジュールルートに読み替え、出力先を本 skill の実行ログに明記する。

### 5.5. テスト設計の確定（実コード整合）と出力ゲート（必須）

手順3.5 のドラフトを、実装・テスト実施（手順5）の結果に整合させて **確定** する（テスト「実施（実行）」とは別責務のテスト「設計（ケース化）」の確定）。`/test-design-from-issue` を finalize モードで呼び、`docs/test/` の次を確定する。

- `docs/test/単体テストマトリクス.md`（TC-XXX）
- `docs/test/トレーサビリティマトリクス.md`（RTM。当該 Issue の行。IT-XXX 列は結合テスト工程が後で記入）

**AC-XXX が無い共通基盤 Issue でも省略しない**。設計書の「実装内容」項目を観点化して TC-XXX を採番する（`/test-design-from-issue` の手順1）。マトリクスは `/test-design-from-issue` が own リポジトリの `docs/test/` に commit/push する（コード本体は手順6で別途コミット）。

finalize で実コード（テストメソッド）と TC-XXX を突合してから、ハードゲートで機械検証する。**exit 0 になるまで手順6（コミット）以降に進まない**。

```bash
/test-design-from-issue $ARGUMENTS finalize
bash .claude/skills/_common/scripts/check-test-matrix.sh docs/test $ARGUMENTS unit
```

NG（exit 1）の場合は不足（単体マトリクスの TC 行・RTM の Issue 行）を補って再実行する。マトリクスの欠如は従来 `review-implementation` の SUGGEST 止まりで取りこぼされていたため、本ゲートで製造の完了条件に組み込む。

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

`gh pr create --base main --head feature/issue-$ARGUMENTS --title "feat(#$ARGUMENTS): <Issue タイトル>" --body-file <一時ファイル>` で、以下のテンプレートを本文として PR を作成する。
PR 本文の `Closes #$ARGUMENTS` により、マージ時に対象 Issue が自動 close される。

```markdown
## 対応 Issue
- Closes #$ARGUMENTS

## 概要
<日本語で機能概要を 3〜5 行で記載>

## 実装内容
- <変更点 1>
- <変更点 2>

## 品質チェック結果
- 静的解析: ✅ 0 violations
- Unit Test: ✅ <件数> passed（バックエンド: 命令 <xx>% / 分岐 <xx>% ・ フロントエンド: ライン <xx>%、いずれも除外後）
- テスト設計: ✅ 単体マトリクス(TC)・RTM 更新済み（check-test-matrix unit 通過）
- ※ 結合テスト(IT) は結合テスト工程（/integration-test-from-design）で別途実施
- Security Review: ✅ OWASP 観点点検済み

## 関連リンク
- Issue: #$ARGUMENTS
- 要件定義: docs/requirements/（claude-poc-docs）
- 設計書: docs/design/（claude-poc-docs）
```

### 8. Issue ステータスの更新

`gh issue comment $ARGUMENTS --body "<レビュー依頼コメント>"` を追記し、
`gh issue edit $ARGUMENTS --remove-label status:ready --add-label status:in-review` でラベルを更新する。

### 9. 最終報告

以下を Markdown テーブルで報告する。

```
| 項目 | 値 |
| --- | --- |
| Issue | #$ARGUMENTS |
| ブランチ | feature/issue-$ARGUMENTS |
| PR URL | https://github.com/<org>/<repo>/pull/<n> |
| Issue ラベル | status:in-review |
| 品質チェック | static-analysis ✅ / unit-test ✅ / test-design(unit ゲート) ✅ / security ✅ |
```

その後、人手レビューが必要であることを明記する。

## 完了条件

- Issue 情報・関連要件定義・関連設計書が確認されている
- feature ブランチが作成されている
- 要件定義の受け入れ条件と設計書に従って実装が完了している
- 単体テスト・静的解析・セキュリティレビューがすべて通過している（**結合テスト・E2E は対象外・別工程**）
- テスト設計（単体マトリクス・RTM）が出力され、`check-test-matrix.sh ... unit` が exit 0（単体マトリクス TC・RTM の Issue 行が揃っている）
- PR が作成され、Body に `Closes #$ARGUMENTS` が含まれている
- Issue ラベルが `status:in-review` に更新されている
- 後続の人手レビューが未実施であることが明記されている

## 注意事項

- 品質チェックで 1 つでも失敗した場合は push / PR 作成を行わない
- 大きな変更が発生する場合（ファイル数 > 30 等）は事前にユーザーへ確認する
- 認証情報は環境変数から参照し、リポジトリにコミットしない
- 製造フェーズの出力（テストマトリクス・RTM・レビュー結果）は **own リポジトリの `docs/test/`** に書く。docs リポジトリ（claude-poc-docs）には書かない（CI で PR に残らないため）
- `.github/workflows/**` の編集は deny ポリシーで禁止されているため、CI 変更が必要な場合は別 Issue として人手で起票・レビューを通すこと
