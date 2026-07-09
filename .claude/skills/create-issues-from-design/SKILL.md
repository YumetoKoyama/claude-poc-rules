---
name: create-issues-from-design
description: 人手レビューで採択済みの設計書から GitHub Issue を起票するときに使う。画面・API（YAML）・IF・テーブル単位の各設計ファイルを解析し、適切な粒度で Issue を分割して起票する。ui-design/handoff/ が存在する場合は README のマッピング表を読み、画面 Issue に prototype 関数参照を埋め込む。レビュー採択前には使用しない。
context: fork
argument-hint: [設計書のパス（省略時は docs/design/ 配下を全件対象）]
---

# 設計書から GitHub Issue を起票する

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

> **Issue の起票先リポジトリ（マルチリポジトリ対応・必須）**: FE/BE は別リポジトリのため、本スキルは Issue の `type:*` ラベルに応じて **起票先リポジトリを出し分ける**（1 回の実行で複数リポジトリに Issue が作られる）。`gh` の全コマンドに `--repo <owner>/<repo>` を明示し、カレントの `origin` に依存しない。
> | ラベル | 起票先 | 判定基準 |
> | --- | --- | --- |
> | `type:screen` | `claude-poc-frontend` | 画面設計（`docs/design/screens/`） |
> | `type:api` / `type:table` | `claude-poc-backend` | API・テーブル設計（`docs/design/api/`・`docs/design/tables/`・`DB定義.md`） |
> | `type:interface` | 実装主体で判定（バッチ IF・投入ジョブ等は `claude-poc-backend`、外部連携が FE 起点なら `claude-poc-frontend`）。判別できない場合は起票を中断しユーザーに確認する | `IF定義.md` の実装レイヤ記載 |
> `<owner>` は `git remote get-url origin` から解決する（`claude-poc-docs`/`claude-poc-rules` と同一 Organization）。解決できない場合は起票を中断し、対象 Organization を人間に確認する。

次の設計書入力をもとに GitHub Issue を起票する。

設計書入力: $ARGUMENTS

## 前提条件

- 要件定義書（`docs/requirements/`）と設計書（`docs/design/`）の両方が人手レビューを経て docs リポジトリの `main` へマージ済みであること（**マージ＝採択**。branch protection で直 push 禁止が前提）。未マージなら起票せず中断し、人手レビュー・マージを依頼する
- **推奨**: 事前に `/tasks-from-design` を実行し `docs/design/tasks.md` を生成しておくと、Issue 粒度・並列優先度・ユーザーストーリー紐づけが明確になる。`tasks.md` が存在する場合は Step 1 でロードし、Issue の受け入れ条件・優先度・並列化ヒントに反映する。存在しない場合は設計書から直接 Issue を生成する（従来動作）
- `gh` CLI がインストール・認証済みであること（`GH_TOKEN` 環境変数。`gh auth status` で確認）。Issue/PR/Project の操作は gh に一本化
- PAT は classic（`repo` + `project`、Organization 所有 Project なら `read:org`）。`GH_TOKEN` は docker-compose が `GITHUB_PERSONAL_ACCESS_TOKEN` からマッピング済み
- 各起票先リポジトリ（`claude-poc-frontend` / `claude-poc-backend` 等）に `.github/ISSUE_TEMPLATE/` のテンプレート（screen / api / interface / table / bug）と必要なラベル（`type:screen` / `type:api` / `type:interface` / `type:table` / `type:bug`、`status:ready` 等）が用意されていること
- UI を Claude Design で作成した場合は、`docs/design/ui-design/handoff/` が **Export 構造そのまま** で格納済みであること（画面単位の分割は不要）

## 成果物

- 各起票先リポジトリ（`claude-poc-frontend` / `claude-poc-backend` 等、`type:*` で出し分け）に起票された GitHub Issue 一覧
- Issue 番号・起票先リポジトリ・タイトル・URL・付与ラベルの Markdown テーブル

## Issue 本文の @ メンション抑止（必須）

GitHub は Issue 本文中の `@名前` を自動的にユーザー / チームへのメンションへ変換し、無関係なアカウントへ通知が飛ぶ。Issue 本文・コメントに `@` で始まるトークンを書くときは、**必ずインラインコード（バッククォート）で囲んでメンション化を防ぐ**。

- 対象例: npm スコープパッケージ（`@playwright/test`・`@reduxjs/toolkit`・`@types/node` 等）、Java アノテーション（`@PreAuthorize`・`@Service` 等）、その他 `@` で始まる識別子。
- NG: 「@playwright/test を使う」のように地の文に裸で書く（メンション化される）。
- OK: 「`@playwright/test` を使う」のようにバッククォートで囲む。
- すでにフェンス付きコードブロックや YAML / コード片の中にある `@` は変換されないため、追加対応は不要。
- 例外: 実装開始トリガーとして人間が投稿する `@claude` コメントは対象外（Issue 本文には書かない）。

## 指示

### 0. 未確定事項の残存チェック（起票前ゲート・工程#2）

設計フェーズ発の未確定事項を Issue 化前に必ず潰す。`docs/design/` 配下を機械的に grep し、**「要確定」「実装で確定」「実装リポジトリで確定」「TBD」「未定」「後で確定」** の文字列が残っている場合は、**起票を中断**して該当ファイル・行を一覧で報告し、人間に確定（または `オープン課題.md` 相当へのクローズ）を依頼する。

```bash
# 残存した未確定マーカーを検出（1 件でもヒットしたら中断）
grep -rnE '要確定|実装で確定|実装リポジトリで確定|(^|[^A-Za-z])TBD([^A-Za-z]|$)|未定|後で確定' docs/design/ || echo "未確定マーカーなし"
```

採択済み設計に未確定が残ったまま Issue 化すると、実装フェーズで設計の意思決定が発生し採択ゲートを迂回する。これを防ぐためのハードゲートである（残存時は exit してユーザーへ）。

### 1. 入力の読み込み

1. 引数で渡されたパスまたは `docs/design/` 配下の設計書を読む。API は `.yaml` で、画面・テーブル・IF は `.md` で書かれていることに注意する。
1.5. **`docs/design/tasks.md` の読み込み（任意）**: ファイルが存在する場合は Read し、タスクの優先度（US1/US2…）・並列可フラグ（[P]）・フェーズ構成を把握する。Issue 起票時の優先度・ラベル・受け入れ条件に反映する（T001 番号を Issue 本文の「関連タスク」欄に記載する）。
2. 設計書が人手レビューで採択済みであることを確認する。未採択または不明なら起票せず中断する。
3. `docs/design/ui-design/handoff/README.md` が存在するか確認する。存在する場合は **画面 ID → prototype 関数のマッピング表** を読み込み、画面 Issue 生成時に参照できるよう内部に保持する。具体的には Markdown テーブルの `| SCR-XXX | ... | wf-screens-*.jsx :: ScrXXXName | ... |` 形式を解析し、`scr_id -> { file, func }` の対応表を作る。
4. **handoff マッピング表の整合チェック（採択前提）**: ステップ 3 で読んだマッピング表の SCR-XXX 集合と、`docs/design/screens/` 配下の `SCR-XXX-*.md` の SCR-XXX 集合を突き合わせる。
   - マッピング表にあるが設計画面が無い、または設計画面にあるがマッピング表に無い SCR-XXX を検出したら、起票を中断してユーザーに不整合を報告する（古い handoff README や画面 ID の欠落を、誤った prototype 参照のまま Issue 化しないため）。
   - 参照する prototype ファイル（`wf-screens-*.jsx` 等）が `docs/design/ui-design/handoff/prototype/` に実在するかも確認する。

### 2. Issue 粒度・ラベル・テンプレートの判断

設計書ファイルの種類に応じて Issue 粒度・ラベル・テンプレートを判断する。

- `docs/design/screens/[scr-id]-*.md` → 画面ごとに 1 Issue（タイトル先頭に `[SCR-XXX]` を含める、ラベル `type:screen`）
- `docs/design/screens/画面遷移.md` → 背景情報として参照、単独 Issue 化しない
- `docs/design/api/[リソース名].yaml` → リソース（YAML ファイル）ごとに 1 Issue。1 リソース YAML 内に複数の HTTP メソッド・パスが含まれるため、1 Issue で全メソッドの実装を扱う。粒度が大きすぎる場合のみ Issue を分割してよい（ラベル `type:api`、タイトル例: `[API] アイテムリソース実装`）
- `docs/design/api/_common.yaml` → 背景情報として参照、単独 Issue 化しない
- `docs/design/IF定義.md` → 外部 IF がある場合のみ起票（ラベル `type:interface`）
- `docs/design/tables/[テーブル名].md` → 原則テーブル単位に 1 Issue（スキーマ変更がない場合は起票しない、ラベル `type:table`）
- `docs/design/DB定義.md` → 全体方針だけの変更で個別テーブル変更がない場合に 1 Issue（ラベル `type:table`）
- `docs/design/概要.md` → 背景情報として参照するが単独 Issue 化しない
- `docs/design/テスト戦略.md` / `シナリオ戦略.md` → 各 Issue の受け入れ条件に反映
- `docs/design/ui-design/brief/`, `docs/design/ui-design/handoff/` → 単独 Issue 化しない。画面 Issue の本文に参照を埋め込む（下記）。

### 3. 画面 Issue への ui-design/handoff 参照の埋め込み

`docs/design/ui-design/handoff/` が存在し、ステップ 1 で作成したマッピング表に該当 scr-id のエントリがある場合、画面 Issue の本文に次のセクションを追加する:

```markdown
## UI 参照（Claude Design Handoff）

- Handoff README: `docs/design/ui-design/handoff/README.md`
- 採用案: <A案 / B案 / 単一案>（README のマッピング表より）
- Prototype 参照: `docs/design/ui-design/handoff/prototype/<file>.jsx :: <FuncName>`
- DS トークン: `docs/design/ui-design/handoff/tokens/colors_and_type.css`（CSS 変数を直接参照、hex 直書き禁止）
- 共通プリミティブ: `docs/design/ui-design/handoff/prototype/wf-primitives.jsx`（既に再実装済みなら再利用）
- 共通シェル: `docs/design/ui-design/handoff/prototype/wf-shell.jsx`

実装時の注意:
- prototype/*.jsx は **デザイン参照用のモック** であり、そのまま本番にコピーしない。
  対象コードベース（React + TypeScript 等）の規約・ライブラリに合わせて **再実装** する。
- カラー・タイポ・スペーシングは `tokens/colors_and_type.css` の CSS 変数を介して参照し、
  hex 値の直書きは禁止する。
- 共通プリミティブとシェルは画面横断資産。最初に着手する画面 Issue で実装し、
  以後の画面 Issue では再利用する。
```

マッピング表が存在しない（ui-design/handoff が無い）場合は、この UI 参照セクションを省略し、画面 Issue 本文の冒頭に「UI 設計は Claude Design 未使用。設計 md の Layout / Content を直接実装する」と明記する。

### 3.4. 横断設計書参照の埋め込み（必須・A-2 対策）

設計→実装の参照チェーン断絶（良質な横断設計書が Issue 本文・実装の必読対象に届かず、共通部品が再発明される）を防ぐため、**すべての実装 Issue（`type:screen` / `type:api` / `type:table` / `type:interface`）** の本文に、次の「横断設計（必読）」セクションを必ず追加する。これにより `implement-from-issue` の必読対象に横断設計書が確実に渡り、`review-implementation` の `common_component` 観点と対応づく。

```
## 横断設計（必読）

実装前に次の横断設計書を必ず読み、定義済みの共通部品・規約を**再発明せず再利用**すること（再実装は review-implementation の `common_component` で BLOCK）:

- 共通部品: `docs/design/共通部品設計.md`（GlobalExceptionHandler / 共通バリデーション / 共通レスポンス整形 / ロギング方式 / ErrorResponse 実装方式。BE は `JwtUtil` 等、FE は `apiClient.ts` 等）
- 認証・認可: `docs/design/セキュリティ設計.md`（および `認可設計.md`。JWT ライフサイクル / `@PreAuthorize` 規約 / テナントフィルタ / CORS）
- API 共通: `docs/design/api/_common.yaml`（共通スキーマは `$ref` で参照、重複定義禁止）
- コード値: `docs/requirements/コード値定義.md` ⇔ `_common.yaml` の enum（値・表示名を一致させる）
```

- `共通部品設計.md` が存在しない場合は、その旨と「共通部品の正典が無いため実装は最小限の自前実装になりうる」リスクを Issue 本文に明記し、設計フェーズへの差し戻しを推奨する。
- API Issue・画面 Issue では、当該 Issue が触れる operationId に対応する `セキュリティ設計.md` / `認可設計.md` の必要ロール行への参照も併記する（認可の二重管理・実装漏れ防止）。


### 3.5. Issue 間の依存順序の明示（S5）

DB → BE API → FE 画面 の実装依存事故（Entity 不在でコンパイル不可など）を防ぐため、各 Issue 本文に依存関係を明示する。

1. 依存の原則: **テーブル Issue（`type:table`） → API Issue（`type:api`） → 画面 Issue（`type:screen`）** の順に依存する。
   - API Issue は、自身が参照するテーブルの Issue に依存する（`docs/design/api/*.yaml` のスキーマ ⇔ `tables/*.md` の対応から特定）。
   - 画面 Issue は、自身が呼ぶ operationId を提供する API Issue に依存する（画面 md の「データ源（operationId）」欄から特定）。
   - 外部 IF Issue（`type:interface`）・バッチ Issue は、関係するテーブル／API Issue に依存する。
2. 起票順序: **依存元（テーブル）から先に起票**し、起票で得た Issue 番号を控える。依存先（API・画面）の本文に `Depends on: #<依存元 Issue 番号>` を記載する（複数依存はカンマ区切り or 複数行）。
   - **リポジトリをまたぐ依存（table/api は `claude-poc-backend`、screen は `claude-poc-frontend`）は、番号だけでは一意にならないため必ず `Depends on: <owner>/claude-poc-backend#<番号>` のように**完全修飾形式（`owner/repo#番号`）**で記載する**（GitHub のクロスリポジトリ参照構文。同一リポジトリ内依存は従来通り `#番号` のみで可）。
3. 既存 Issue を更新する場合（冪等更新）も、`Depends on:` 行を最新の番号で維持する。
4. 起票結果テーブル（後述）に「依存（Depends on）」列を追加し、依存グラフを人間が確認できるようにする（クロスリポジトリ依存は起票先リポジトリ列と合わせて確認できるようにする）。

> `implement-from-issue` の手順 1 には「`Depends on:` の各 Issue がクローズ済みか確認。未クローズなら中断」のゲートがある（依存元未マージの状態で下流実装を開始させない）。クロスリポジトリ依存の場合は `gh issue view <owner>/<repo>#<番号> --json state` のように **`--repo` ではなく完全修飾 Issue 参照**で状態確認する。

### 3.6. 移行（MIG-XXX）の対応 Issue 整合チェック（工程#4）

`docs/requirements/移行要件.md`（または設計の対応箇所）に **MIG-XXX が定義されているのに、それを実現する対応 Issue（初期データ投入・マスタ投入を担うバッチ IF / `type:interface` or `type:table` の Issue）が起票対象に無い**場合は、**エラーとして中断**し、不足している MIG-XXX と必要な Issue 種別を報告する。

```bash
# MIG-XXX の抽出（要件 → 設計の順に探す。「移行なし」明記時はスキップ可）
grep -rnoE 'MIG-[0-9]{3}' ../claude-poc-docs/docs/requirements/移行要件.md docs/ 2>/dev/null | sort -u
```

- 各 MIG-XXX について、`IF定義.md` / `バッチ設計.md` に対応するバッチ IF（投入ジョブ）が設計されているかを確認し、設計されていれば対応 Issue を起票、設計が無ければ「設計欠落」として中断（設計フェーズへ差し戻し）する。
- 「移行なし」と明記されている場合（MIG-XXX が 0 件、かつ移行要件.md にその旨の記載）はこのチェックをスキップし、その旨をサマリに残す。

### 4. 重複検出と起票

1. 起票前に、パス解決節の表で決定した起票先リポジトリを **すべての `gh` コマンドに `--repo <owner>/<repo>` で明示**する（例: `gh issue list --repo <owner>/claude-poc-frontend --search "[SCR-XXX] in:title" --state open --json number,title`）。**冪等性ルール**: 画面 Issue はタイトル先頭の `[SCR-XXX]` で既存 Issue を検索し、同一 `[SCR-XXX]` の open Issue が見つかった場合は **新規作成せず**、本文の差分を `gh issue edit --repo <owner>/<repo> <番号> --body-file <一時ファイル>` で更新する（または変更点を `gh issue comment --repo <owner>/<repo>` で追記する）。新規起票は `gh issue create --repo <owner>/<repo> --title "..." --body-file <一時ファイル> --label "type:<種別>" --label "status:ready"` で行う。API Issue も同様にリソース名で照合する。`[SCR-XXX]` 一致が無い場合のみ新規起票する。判断に迷う近似一致はユーザーに確認を取る。
2. Issue 本文はすべて日本語で記述する。受け入れ条件はチェックボックス（`- [ ]`）で列挙する。
3. 画面 Issue の受け入れ条件には少なくとも次を含める:
   - 設計 md の「画面概要」「入力」「出力・表示内容」「バリデーションメッセージ」が実装に反映されている
   - 共通の状態（empty / loading / error / 権限不足）が `_共通.md` の規約通りに表現されている（ui-design/handoff がある場合は prototype の状態切替と一致）
   - 画面遷移が `docs/design/screens/画面遷移.md` と一致する
   - 関連する受け入れ条件（AC-XXX）に対応するユニットテスト or E2E テストが存在する

### 5. 起票結果の報告

起票結果をテーブル形式で報告し、後続の `/implement-from-issue <ISSUE-NUMBER>` を使って実装に進めることを明記する。

| Issue # | リポジトリ | タイトル | ラベル | URL | 依存（Depends on） | UI参照 |
|--------|--------|--------|------|-----|------|------|
| #123 | claude-poc-frontend | [SCR-100] 配送依頼企業ダッシュボード | type:screen | https://... | owner/claude-poc-backend#110, owner/claude-poc-backend#115 | wf-screens-shipper.jsx :: Scr100DashA |

## 完了条件

- 要件定義書と設計書がともに採択済みであることが確認されている。
- 画面・API・IF・テーブル単位の各設計ファイルに対応する Issue が起票されている。
- 起票した Issue 番号・タイトル・URL・付与ラベルが報告されている。
- ui-design/handoff/ が存在する場合、画面 Issue の本文に prototype 関数参照・トークン参照・共通プリミティブ参照が埋め込まれている。
- 設計書内に未確定マーカー（要確定 / 実装で確定 / TBD 等）が残っていないことを確認済みである（工程#2）。
- 各下流 Issue の本文に `Depends on: #XX`（DB → BE → FE の依存順序）が記載されている（S5）。
- MIG-XXX が定義されている場合、対応する移行 Issue（バッチ IF / 投入ジョブ）が起票されている。または「移行なし」が確認されている（工程#4）。
- 後続工程（`/implement-from-issue <ISSUE-NUMBER>`）が未着手であることが明記されている。
