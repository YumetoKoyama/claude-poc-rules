# ① プロンプト生成ルール（skill・agent 作成ルール）

最終更新: 2026-05-27

本文書は、AI に作業を委ねる際に書くプロンプト（slash command の本文、skill の SKILL.md、対話プロンプト）の **設計規約** と **再利用できる型** をまとめたものです。原則と実例を併記します。

---

## 1. 設計の 7 原則

| # | 原則 | 趣旨 |
|---|------|------|
| 1 | 責務を 1 つに絞る | 1 つの skill / プロンプトは 1 つの責務だけを担う（produce / review / fix / orchestrate のいずれか） |
| 2 | 入力と出力を明示する | 「どのファイルを読み、どこに何を書くか」を冒頭で列挙する |
| 3 | スコープ境界を明記する | 「ここまでが責務、ここから先には進まない」を本文に書く |
| 4 | 暗黙補完を禁止する | 不明点は `オープン課題.md` 等に落とす。AI に勝手に決めさせない |
| 5 | 既存ファイルは差分追加 | 完全上書きを避け、加算型の更新を指示する |
| 6 | 機械可読な出力 | レビュー・判定結果は JSON 等の構造化形式で返させる |
| 7 | テンプレートを参照させる | フォーマット差分を埋めるため、雛形ファイルを `[link](path.md)` で指す |

> 上記の出典: `.claude/skills/requirements-from-input/SKILL.md`、`.claude/skills/review-requirements/SKILL.md`、`docs/architecture/skill-orchestration.md`。

---

## 2. プロンプト構造のテンプレート

### 2.1 汎用テンプレート（任意の AI 作業に適用可能）

```markdown
## 役割
（この skill / プロンプトが担う 1 つの責務）

## 入出力
- 入力: <パス・引数・前提ファイル>
- 出力: <生成・更新するファイル>
- 出力（標準出力）: <orchestrator が読み取る値があれば 1 行で>

## 手順
1. <決定論的な準備（state Read など）>
2. <AI 判断が必要な本体作業>
3. <出力の書き出し>
4. <次工程に進まないことの確認>

## スコープ外
- <この skill が触らないファイル・領域>
- <次フェーズに渡る判断>

## 参照
- [テンプレート](path.md)
- [上位ガバナンス](../../docs/process/README.md)
```

### 2.2 skill 用 frontmatter テンプレート

```yaml
---
name: <phase>-<role>           # phase: requirements|design|implement, role: from-input|loop|review|fix
description: <150字程度。トリガー語と「いつ使うか」を含める>
context: fork                   # produce/review/fix は fork。orchestrator は省略
allowed-tools: <最小限>          # Bash, Read, Glob, Grep, Edit, Write, SlashCommand など
argument-hint: <あれば>          # [画面ID] / <ISSUE番号> 等
disable-model-invocation: true   # orchestrator のみ。意図しない自動起動を防ぐ
---
```

### 2.3 review skill 出力（JSON）テンプレート

```json
{
  "phase": "requirements|design|implement",
  "iteration": 1,
  "summary": "<1〜2文の総評>",
  "findings": [
    {
      "id": "F-001",
      "severity": "BLOCK|SUGGEST|NIT",
      "category": "completeness|consistency|traceability|security|...",
      "target": "<対象ファイルまたは設計要素>",
      "issue": "<問題の説明>",
      "suggested_fix": "<修正案。fix skill がここを起点にする>"
    }
  ],
  "counts": { "block": 0, "suggest": 0, "nit": 0 }
}
```

---

## 3. skill 作成ルール

### 3.1 命名・配置

- ディレクトリ名と `name` フィールドは一致させる（kebab-case）。
- 役割は接頭辞で表す: `requirements-from-input`（produce）、`review-requirements`（review）、`fix-requirements`（fix）、`requirements-loop`（orchestrator）。
- 共有スクリプトは skill ではなく `.claude/skills/_common/scripts/` 配下に置く。

### 3.2 `context: fork` の判断基準

| skill 種別 | fork する？ | 理由 |
|------------|------------|------|
| produce（生成） | はい | 後段に思考プロセスを引きずらせない |
| review（独立判定） | **必須** | produce の思考に汚染されず、書かれた成果物だけで判定するため |
| fix（修正適用） | はい | review JSON を一次入力として独立適用する |
| orchestrator（ループ制御） | **しない** | main session で state とループ状態を保持し、sub-skill 連鎖を制御する |

> 出典: `docs/architecture/skill-orchestration.md` §1（指針 4）、`.claude/skills/*-loop/SKILL.md` の frontmatter。

### 3.3 `allowed-tools` の最小化

- produce: `Read, Write, Edit, Glob, Grep, Bash`
- review: `Read, Glob, Grep, Write`（Edit/Bash は通常不要）
- fix: `Read, Edit, Write, Glob, Grep, Bash`
- orchestrator: `Bash, Read, Write, SlashCommand`

### 3.4 「進まない」の明示

スコープ境界を本文の最後に必ず 1 段落で書く。例:

> このスキルは要件定義成果物の作成だけを行います。設計・実装・テストには進みません。`requirements-loop` から呼ばれた場合は、生成後に制御をオーケストレータへ返してください。

### 3.5 「並列実行」の書き方（Pattern 2）

3 つの品質ゲート（UT / 静的解析 / E2E）のように **依存のない sub-skill** は、produce skill 内で「並列で起動する」と明示し、orchestrator では扱わない。

```markdown
## 品質ゲート（並列）
以下を **並列に** 起動し、すべて成功するまで次へ進まない。
- /unit-test-from-design
- /static-analysis-remediation
- /e2e-from-design

いずれかが失敗した場合は /failure-investigator を起動し、根本原因を切り分けてから再実行する。
```

> 出典: `.claude/skills/implement-from-issue/SKILL.md`、CLAUDE.md「開発フロー」§8。

---

## 4. プロンプトに必ず入れる要素（チェック）

- [ ] 入力ファイル・引数の **完全リスト**
- [ ] 出力ファイルの **完全リストと配置先**（命名規約付き）
- [ ] 既存ファイルは **差分追加** の指示
- [ ] 不明点の **落とし先**（`オープン課題.md` 等）
- [ ] **次工程に進まない** 旨の宣言
- [ ] 参照する **テンプレートファイルへのリンク**
- [ ] 用語は `docs/requirements/用語集.md` と整合
- [ ] レビュー系なら **JSON 出力スキーマ** の明示
- [ ] orchestrator なら **state.json の読み書き手順**

---

## 5. agent（subagent）の扱い

本プロジェクトでは **agent（Agent Teams）は使用しない**。理由は次の通り。

1. experimental 機能であり、本番運用に耐える保証がない。
2. 並列実行は Pattern 2（同一 produce skill 内で並列起動）で代替可能。
3. state とループ制御を main session に置く方が、人手介入とデバッグが容易。

> 出典: CLAUDE.md「スキルオーケストレーション運用ガイダンス」、`docs/architecture/skill-orchestration.md` §1（指針 4・5）。

例外的に agent 的な独立判定が欲しい場面では、`context: fork` の review skill で十分代替できる。判定結果は JSON で受け取り、orchestrator が次の遷移を決める。

---

## 6. ノウハウ集（運用で効いている型）

### N-01: 「成果物配置を冒頭で列挙する」

produce skill の冒頭で出力ファイル名を箇条書きにすると、AI が「どのファイルを作るか」を迷わない。`requirements-from-input` は 8 ファイル、`design-from-requirements` はファイル単位の粒度（screen / api / table）まで指定して効果を上げている。

### N-02: 「テンプレートをリンクで指す」

`[requirements-template.md](requirements-template.md)` のようにリンクで雛形を参照させると、フォーマット差分を AI が自力で埋めやすい。本文に雛形を直書きしない（メンテ性が落ちる）。

### N-03: 「suggested_fix を必ず書かせる」

review JSON の各 finding に `suggested_fix` を必須にすると、fix skill がそれを起点に修正でき、判断ロスが減る。

### N-04: 「stage 遷移は決定論スクリプトに分離」

ループの停止判定（BLOCK 0 か iteration 上限か）を AI 判断に任せず、`record-review.sh` のような独立スクリプトで処理する。SKILL.md には「ここでスクリプトを呼ぶ」とだけ書く。

### N-05: 「fork skill には Read で必要ファイルを順に列挙」

fork した skill は会話履歴を持たないので、必要なファイルを `Read` する手順をプロンプトに 1 つずつ並べる。存在チェック（「存在しないものはスキップ」）も明記する。

### N-06: 「produce skill は 1 ファイルあたり最大長を意識」

機能単位・画面単位でファイルを分割すると、後工程の Read コストとマージコンフリクトが下がる。`functional/[機能名].md` や `screens/[scr-id]-*.md` の運用が好例。

---

## 7. claude-poc 固有ルール

### 7.1 言語

- 応答・成果物・コメントは **日本語** で書く（CLAUDE.md「共通応答ルール」と整合）。
- コード識別子は英語、自然言語ドキュメントは日本語。

### 7.2 画面 ID

- 画面 ID は **SCR-NNN**（3 桁ゼロ埋め）。要件・設計・テスト・Issue・PR で同じ ID を引用する。
- skill のプロンプトでも `<scr-id>` を引数として受け取れる場合はそうする。

### 7.3 API 設計の参照

- OpenAPI 3.1。1 リソース = 1 ファイル（同リソースの全 HTTP メソッドを 1 YAML に集約）。共通スキーマは `docs/design/api/_common.yaml` に集約し `$ref` で参照。
- skill が API 定義を生成する場合、`_common.yaml` の存在チェックと差分追加を必ず手順に含める。

### 7.4 DB 設計の参照

- 全体方針と全体 ER 図は `docs/design/DB定義.md`。テーブル単位は `docs/design/tables/[テーブル名].md` で **部分 ER 図必須**。
- skill が DB を扱う場合、Entity・Repository・DDL・`docs/design/tables/*.md` の四点整合を確認する手順を入れる。

### 7.5 Issue 起票テンプレ

- `.github/ISSUE_TEMPLATE/` の **screen / api / interface / table / bug** の 5 種類を使い分ける。
- タイトル規約: `[SCR-XXX] <画面名>`、`[API] <リソース名>`、`[IF] <IF 名>`、`[TBL] <テーブル名>`、`[BUG] <概要>`。1 API Issue = 1 リソース YAML（同リソースの全 HTTP メソッドを含む）。
- ラベルは `type:<種別>` と `status:ready` を初期付与。

---

## 8. アンチパターン

| # | アンチパターン | 代わりにすべきこと |
|---|----------------|--------------------|
| A1 | 1 つの skill に複数責務を詰め込む | produce / review / fix / orchestrate に分離 |
| A2 | 状態を会話履歴に分散させる | `.skills-state/<phase>/state.json` に集約 |
| A3 | レビュー判定を自然文で返す | JSON（BLOCK/SUGGEST/NIT）で返す |
| A4 | 全処理を SKILL.md に書く | 決定論部分は `_common/scripts/*.sh` に分離 |
| A5 | review skill を fork しない | produce の思考に汚染される。fork 必須 |
| A6 | orchestrator を fork する | ループ状態が失われる。fork しない |
| A7 | テンプレートを SKILL.md に直書き | 別ファイル化してリンクで参照 |
| A8 | 不明点を AI に補完させる | `オープン課題.md` に落とす |

---

## 9. 関連文書

- [README.md](README.md) — 索引
- [02-review-criteria.md](02-review-criteria.md) — レビュー基準（本文書の出力フォーマットと対応）
- [03-ai-usage-scenes.md](03-ai-usage-scenes.md) — どの工程でこのルールを適用するか
- [04-development-flow.md](04-development-flow.md) — フロー全体の中での位置づけ
- [05-test-process.md](05-test-process.md) — テスト生成 skill のプロンプト固有要素
- [06-issue-management.md](06-issue-management.md) — Issue 関連 skill のラベル更新規約
- `CLAUDE.md` — 最上位の規約
- `docs/architecture/skill-orchestration.md` — オーケストレーション設計の根拠
