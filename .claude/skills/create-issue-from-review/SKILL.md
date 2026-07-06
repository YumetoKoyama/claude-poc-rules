---
name: create-issue-from-review
description: レビュー指摘（review-implementation-overall 等の指摘テキストまたはレビュー結果 md）から、GitHub Issue 起票用の文章（タイトル・本文・ラベル・起票先リポ・gh コマンド例）を生成する。生成のみで起票は行わない（起票は人手＝採択ゲート）。「この指摘を Issue にして」「レビュー結果から Issue 文章を作って」と言われた時に使う。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Write
argument-hint: [指摘テキスト | レビュー結果mdパス [BLOCK|SUGGEST|all]]
---

# レビュー指摘から GitHub Issue 起票文章を生成する

> **位置づけ**: `review-implementation-overall` 等のレビュー指摘を、人手が起票できる Issue 文章に整形する**生成専用**スキル。**`gh issue create` は実行しない**（Claude・skill が自ら Issue 起票・`@claude` コメントをしてはならない、という採択ゲート思想に従う）。起票・`@claude` コメントによる実装開始は人間の明示アクション。
>
> **全体レビュー（8.8）からの Issue 化フロー（S10）**: 本スキルは開発フローの **8.8 `/review-implementation-overall`** の後段に位置する。フロー上の処理は次のとおり:
> 1. `/review-implementation-overall` がフィーチャ横断の指摘（BLOCK/SUGGEST/NIT）を `docs/test/レビュー結果/overall-*.md` と JSON に出力する。
> 2. 本スキル（`/create-issue-from-review <overall md パス> [BLOCK|SUGGEST|all]`）で、指摘を 1 件 1 Issue の起票文章へ整形する（裏取り → 起票先リポ・ラベル決定 → 文章生成 → md 保存）。
> 3. **人間が** 提示された gh コマンドで Issue を起票し、対象 Issue に `@claude` をコメントして実装を開始する（採択ゲート＝人間の明示アクション。自動ループは設けない）。
> 4. 修正は通常の `/implement-loop <ISSUE>` で対応し、必要なら再度 8.8 の全体レビューを回す（review → 修正 → 再 review の人手主導サイクル）。
> 設計側に起因する指摘（設計⇔実装の食い違いで設計が誤り）は、実装 Issue ではなく docs リポへの設計変更（`/design-amendment`）として扱う方針を本文冒頭の「方針確定（人手）」タスクに明記する。
>
> **パス解決（マルチリポジトリ対応）**: 親アンブレラ（claude-poc-rules、カレント直下に `claude-poc-backend/` 等が在る）から実行する想定。設計書・要件は `claude-poc-docs/docs/design/`・`claude-poc-docs/docs/requirements/` を参照する。子リポ直下で実行された場合はリポ相対パス、docs は `../claude-poc-docs/` とする。

入力: $ARGUMENTS

## 入力の解釈（2 形態）

1. **指摘テキスト**（例: `/create-issue-from-review operationId listJobs の @PreAuthorize が ...`）
   → その 1 指摘から 1 Issue 文章を生成する。
2. **レビュー結果 md のパス**（例: `/create-issue-from-review claude-poc-backend/docs/test/レビュー結果/overall-all-20260612.md BLOCK`）
   → ファイル先頭（最新実行セクション）の「指摘一覧」テーブルを解析し、指定重大度の指摘から一括生成する。
   - 第 2 引数: `BLOCK`（既定）/ `SUGGEST`（BLOCK+SUGGEST）/ `all`（NIT 含む）
   - `対応状況` が「対応済み」「見送り」の行はスキップし、その旨を報告する。

引数がパスとして実在すれば形態 2、それ以外は形態 1 と判定する。

## 手順

### 1. 裏取り（推測で書かない）

指摘ごとに、可能な範囲で根拠を実ファイルで確認する。

- 該当コード（`claude-poc-backend/src/...` 等）を Read し、指摘内容（行番号・アノテーション・フィールド名等）が現存するか確認する。**既に修正済みなら Issue 化せず、その旨を報告する**。
- 引用されている設計書（`claude-poc-docs/docs/design/認可設計.md` 等）の該当セクションを Read し、設計側の記述を本文に引用できるようにする。
- 確認できないもの（リポ不在・パス不明）は本文の根拠欄に「未検証」と明記する。確認できないことを理由に中断はしない。
- 関連 ID（UC / AC / BR / SCR-XXX / SEQ-XXX / operationId / MSG-XXX / TC-XXX）を指摘文・設計書から抽出する。

### 2. 起票先リポとラベルの決定

- **起票先**: 指摘の `該当` パスのリポ名前置から決定する（`claude-poc-backend/...` → backend リポ）。**設計書・実装のどちらに合わせるか人手の方針確定が必要な指摘**は、修正対象が未確定のため既定で**実装側リポ**に起票し、本文冒頭に「方針確定（人手）」タスクを置く。リポをまたぐ指摘（cross_repo_consistency）は**主修正先のリポに 1 Issue** とし、相手リポの修正は本文のタスクリストに含める（必要なら人手で分割）。
- **ラベル**: 既定 `type:bug`（設計⇔実装の乖離・実装不備）。設計書のみの修正は docs リポへ `type:design` 相当。未実装系（design_coverage）は対象種別に応じ `type:screen` / `type:api` / `type:table`。**リポに存在しないラベルは作成せず「ラベル案」として提示に留める**。
- 重大度はタイトルに含める（後述）。

### 3. Issue 文章の生成

1 指摘 = 1 Issue。次のテンプレートで生成する。

```markdown
# タイトル
[REV][<BLOCK|SUGGEST|NIT>] <80 字以内の要約。関連 ID（SCR-XXX / operationId 等）があれば含める>

# 本文

## 概要
<指摘内容を 2〜4 文で。何が・どこで・設計のどこと食い違うか>

## 該当箇所
- 実装: `<リポ名/path:line>`
- 設計: `<設計書パス + セクション>`

## 根拠（裏取り結果）
- 実装側: <Read で確認した現状の引用（コード断片・行番号）。未検証ならその旨>
- 設計側: <設計書該当箇所の引用>

## 影響
<放置した場合の業務・セキュリティ・他リポへの影響>

## 対応方針
<レビューの推奨対応をタスクリスト化。選択肢が複数あり人手判断が要る場合は
「- [ ] 方針確定（人手）: 案A / 案B」を先頭に置く>

## 完了条件
<設計書と実装の一致確認・テスト（TC-XXX 追加等）・RTM 更新など検証可能な条件>

## 関連
- 関連 ID: <UC / AC / BR / SCR / operationId / MSG / TC>
- 出典: <レビュー結果 md のパスと実行日時セクション>（タイトルの [REV] はレビュー指摘起点 Issue を示す接頭辞）
```

**`@` メンション抑止（必須）**: 本文中の `@PreAuthorize`・`@JsonProperty` 等、`@` で始まるトークンは必ずバッククォートで囲む（GitHub のメンション化による誤通知防止）。`@claude` は本文に書かない。

### 4. 出力

1. **ファイル保存**: 起票先リポの `docs/test/レビュー結果/issues/<YYYYMMDD>-<連番2桁>-<要約スラッグ>.md` に 1 指摘 1 ファイルで Write する（ディレクトリが無ければ作成。既存ファイルと連番が衝突しないよう `ls` で確認）。
2. **チャット出力**: 生成した Issue 文章（単発時は全文、一括時は「ファイルパス / タイトル / 起票先リポ / ラベル案」の一覧表）と、人手起票用の gh コマンド例を提示する。

```bash
# 人手で実行する例（このスキルは実行しない）
gh issue create --repo <owner>/<起票先リポ> \
  --title "<タイトル>" \
  --body-file "<保存した md の本文部分>" \
  --label "type:bug"
```

3. （任意・読み取りのみ）`gh issue list --repo <起票先リポ> --search "<キーワード>"` が利用可能なら既存 Issue との重複候補を確認し、見つかれば一覧に併記する。利用不可ならスキップ。

## 注意事項

- **このスキルは Issue を起票しない・コードや設計書を書き換えない**。出力は Issue 文章 md とチャット表示のみ。
- 既往の Issue 単位レビュー（`docs/test/レビュー結果/implement-issue-*.md`）で「見送り」判断済みの指摘は Issue 化せず、参照に留める。
- 技術スタック・実装規約は本スキルに再掲せず、必要時に各リポの `.claude/rules/` を Read して参照する（矛盾時は frontend ルールが正）。
- 応答・成果物は日本語で記述する。
