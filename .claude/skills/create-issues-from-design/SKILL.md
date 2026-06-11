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

次の設計書入力をもとに GitHub Issue を起票する。

設計書入力: $ARGUMENTS

## 前提条件

- 要件定義書（`docs/requirements/`）と設計書（`docs/design/`）の両方が人手レビューを経て docs リポジトリの `main` へマージ済みであること（**マージ＝採択**。branch protection で直 push 禁止が前提）。未マージなら起票せず中断し、人手レビュー・マージを依頼する
- `gh` CLI がインストール・認証済みであること（`GH_TOKEN` 環境変数。`gh auth status` で確認）。Issue/PR/Project の操作は gh に一本化
- PAT は classic（`repo` + `project`、Organization 所有 Project なら `read:org`）。`GH_TOKEN` は docker-compose が `GITHUB_PERSONAL_ACCESS_TOKEN` からマッピング済み
- 対象リポジトリに `.github/ISSUE_TEMPLATE/` のテンプレート（screen / api / interface / table / bug）と必要なラベル（`type:screen` / `type:api` / `type:interface` / `type:table` / `type:bug`、`status:ready` 等）が用意されていること
- UI を Claude Design で作成した場合は、`docs/design/ui-design/handoff/` が **Export 構造そのまま** で格納済みであること（画面単位の分割は不要）

## 成果物

- 対象リポジトリに起票された GitHub Issue 一覧
- Issue 番号・タイトル・URL・付与ラベルの Markdown テーブル

## Issue 本文の @ メンション抑止（必須）

GitHub は Issue 本文中の `@名前` を自動的にユーザー / チームへのメンションへ変換し、無関係なアカウントへ通知が飛ぶ。Issue 本文・コメントに `@` で始まるトークンを書くときは、**必ずインラインコード（バッククォート）で囲んでメンション化を防ぐ**。

- 対象例: npm スコープパッケージ（`@playwright/test`・`@reduxjs/toolkit`・`@types/node` 等）、Java アノテーション（`@PreAuthorize`・`@Service` 等）、その他 `@` で始まる識別子。
- NG: 「@playwright/test を使う」のように地の文に裸で書く（メンション化される）。
- OK: 「`@playwright/test` を使う」のようにバッククォートで囲む。
- すでにフェンス付きコードブロックや YAML / コード片の中にある `@` は変換されないため、追加対応は不要。
- 例外: 実装開始トリガーとして人間が投稿する `@claude` コメントは対象外（Issue 本文には書かない）。

## 指示

### 1. 入力の読み込み

1. 引数で渡されたパスまたは `docs/design/` 配下の設計書を読む。API は `.yaml` で、画面・テーブル・IF は `.md` で書かれていることに注意する。
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

### 4. 重複検出と起票

1. 起票前に `gh issue list --search "[SCR-XXX] in:title" --state open --json number,title` でタイトルの近似検索を行う。**冪等性ルール**: 画面 Issue はタイトル先頭の `[SCR-XXX]` で既存 Issue を検索し、同一 `[SCR-XXX]` の open Issue が見つかった場合は **新規作成せず**、本文の差分を `gh issue edit <番号> --body-file <一時ファイル>` で更新する（または変更点を `gh issue comment` で追記する）。新規起票は `gh issue create --title "..." --body-file <一時ファイル> --label "type:<種別>" --label "status:ready"` で行う。API Issue も同様にリソース名で照合する。`[SCR-XXX]` 一致が無い場合のみ新規起票する。判断に迷う近似一致はユーザーに確認を取る。
2. Issue 本文はすべて日本語で記述する。受け入れ条件はチェックボックス（`- [ ]`）で列挙する。
3. 画面 Issue の受け入れ条件には少なくとも次を含める:
   - 設計 md の「画面概要」「入力」「出力・表示内容」「バリデーションメッセージ」が実装に反映されている
   - 共通の状態（empty / loading / error / 権限不足）が `_共通.md` の規約通りに表現されている（ui-design/handoff がある場合は prototype の状態切替と一致）
   - 画面遷移が `docs/design/screens/画面遷移.md` と一致する
   - 関連する受け入れ条件（AC-XXX）に対応するユニットテスト or E2E テストが存在する

### 5. 起票結果の報告

起票結果をテーブル形式で報告し、後続の `/implement-from-issue <ISSUE-NUMBER>` を使って実装に進めることを明記する。

| Issue # | タイトル | ラベル | URL | UI参照 |
|--------|--------|------|-----|------|
| #123 | [SCR-100] 配送依頼企業ダッシュボード | type:screen | https://... | wf-screens-shipper.jsx :: Scr100DashA |

## 完了条件

- 要件定義書と設計書がともに採択済みであることが確認されている。
- 画面・API・IF・テーブル単位の各設計ファイルに対応する Issue が起票されている。
- 起票した Issue 番号・タイトル・URL・付与ラベルが報告されている。
- ui-design/handoff/ が存在する場合、画面 Issue の本文に prototype 関数参照・トークン参照・共通プリミティブ参照が埋め込まれている。
- 後続工程（`/implement-from-issue <ISSUE-NUMBER>`）が未着手であることが明記されている。
