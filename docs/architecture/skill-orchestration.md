# スキルオーケストレーション設計

最終更新: 2026-05-26

## 1. 位置づけと方針

本プロジェクトの AI 駆動開発は、**Claude Code の skill 連鎖だけ**でワークフローを組み立てる。Agent Teams は使用しない（experimental かつ並列実行は Pattern 2 で代替可能）。

設計上の指針は次の 7 点。

1. **how は skill、access は MCP** — 業務ロジックは skill、外部接続は MCP に分離する
2. **状態は単一の JSON ファイル** — `.skills-state/<phase>/state.json` を真実の源とする
3. **3 層責務分離**
   - 第1層（決定論）: シェルスクリプト（パス計算・JSON 読み書き・git 操作）
   - 第2層（条件分岐）: SKILL.md の手順（stage 値に応じた sub-skill 呼び出し）
   - 第3層（AI 判断）: 各 sub-skill の本文（要件作成・レビュー判定・修正実装）
4. **`context: fork` をデフォルト** — ただし orchestrator skill 自身は fork しない
5. **改善ループは最大 max_iterations 回**（既定 3。`init-state.sh` の第 3 引数で変更可）— 上限到達時は人手レビューへエスカレーション
6. **review skill の出力は機械可読 JSON** — BLOCK / SUGGEST / NIT で重大度を分離
7. **fix skill は BLOCK + SUGGEST のみを対象** — NIT は無視

## 2. 連携パターン

参考: [Claude Code のスキルをオーケストレーション](https://zenn.dev/ino_h/articles/2026-05-15-claude-code-skills-orchestration) の Pattern 2 / 3 / 4。

- **Pattern 4 (Iterative Loop)**: 各 phase の `*-loop` orchestrator が produce → review → fix → review を回す
- **Pattern 3 (Conditional Routing)**: orchestrator が state.stage の値で分岐
- **Pattern 2 (Parallel Fan-Out)**: implement phase の品質ゲート（UT / 静的解析 / E2E）を並列化

## 3. ディレクトリ構成

```
.claude/skills/
├── _common/                              # 共通スクリプト（skill ではない）
│   └── scripts/
│       ├── init-state.sh                 # state JSON 初期化（決定論）
│       ├── advance-state.sh              # stage 遷移と iteration++（escalate 判定はしない）
│       ├── record-review.sh              # review JSON のメタを state に反映 + history 追記 + PASS/escalate 判定
│       ├── summarize-state.sh            # 最終サマリ生成
│       ├── validate-review-json.sh       # review JSON の妥当性検証
│       ├── check-truncation.sh           # 成果物のファイル切断・破損検出
│       ├── check-skill-names.sh          # *-loop の SlashCommand 参照名が実 skill 名に解決できるか検証
│       └── approve-phase.sh              # 人手採択マーカー（approved.json）の記録/取消
│
├── requirements-from-input/              # phase 1: produce（既存）
├── design-from-requirements/             # phase 2: produce（既存）
├── implement-from-issue/                 # phase 3: produce（既存）
│
├── review-requirements/                  # phase 1: review（新規, context: fork）
├── review-design/                        # phase 2: review（新規, context: fork）
├── review-implementation/                # phase 3: review（新規, context: fork）
│
├── fix-requirements/                     # phase 1: fix（新規, context: fork）
├── fix-design/                           # phase 2: fix（新規, context: fork）
├── fix-implementation/                   # phase 3: fix（新規, context: fork）
│
├── requirements-loop/                    # phase 1: orchestrator（新規, NO fork）
├── design-loop/                          # phase 2: orchestrator（新規, NO fork）
└── implement-loop/                       # phase 3: orchestrator（新規, NO fork）

.skills-state/                            # 状態保持（gitignore 済み）
├── requirements/
│   ├── state.json
│   ├── approved.json                     # 人手採択マーカー（approve-phase.sh が生成）
│   ├── round-1-review.json
│   └── round-2-review.json
├── design/
└── implement/
```

## 4. state JSON スキーマ

`.skills-state/<phase>/state.json`:

```json
{
  "phase": "requirements",
  "iteration": 1,
  "max_iterations": 3,
  "stage": "review",
  "artifact_path": "docs/requirements/",
  "extra_args": "docs/requirements-input/sample.md",
  "last_review_path": ".skills-state/requirements/round-1-review.json",
  "review_counts": { "block": 2, "suggest": 5, "nit": 3 },
  "passed": false,
  "escalated": false,
  "history": [
    { "iteration": 1, "stage": "produce", "completed_at": "2026-05-26T01:00:00Z" },
    { "iteration": 1, "stage": "review",  "block": 2, "completed_at": "2026-05-26T01:05:00Z" }
  ]
}
```

| フィールド | 型 | 用途 |
| --- | --- | --- |
| `phase` | string | `requirements` / `design` / `implement` |
| `iteration` | int | 現在の試行回数（1 始まり） |
| `max_iterations` | int | 上限（既定: 3） |
| `stage` | string | `produce` / `review` / `fix` / `done` / `escalate` |
| `artifact_path` | string | 当該 phase の成果物パス |
| `extra_args` | string | produce skill へ渡す追加引数 |
| `last_review_path` | string | 最新 review JSON のパス |
| `review_counts` | object | 直近 review の BLOCK / SUGGEST / NIT 件数 |
| `passed` | bool | 終了条件（BLOCK == 0）に到達したか |
| `escalated` | bool | 上限到達で人手エスカレーションされたか |
| `history` | array | 監査ログ。各 stage 完了時に追記 |

## 5. review JSON スキーマ

`.skills-state/<phase>/round-N-review.json`:

```json
{
  "phase": "requirements",
  "iteration": 1,
  "reviewed_at": "2026-05-26T01:05:00Z",
  "overall": "FAIL",
  "summary": "要件定義の完成度: 3 件の BLOCK と 5 件の SUGGEST。AC-XXX の表記揺れと業務ルール ID の欠落が主要因。",
  "findings": [
    {
      "severity": "BLOCK",
      "path": "docs/requirements/概要.md",
      "line": 42,
      "category": "completeness",
      "message": "受け入れ条件 AC-003 が functional/login.md から参照されているが未定義",
      "suggested_fix": "概要.md の受け入れ条件節に AC-003 を追加する"
    },
    {
      "severity": "SUGGEST",
      "path": "docs/requirements/用語集.md",
      "line": null,
      "category": "naming",
      "message": "「ユーザ」と「ユーザー」が混在",
      "suggested_fix": "「ユーザー」に統一"
    },
    {
      "severity": "NIT",
      "path": "docs/requirements/業務ルール.md",
      "line": 12,
      "category": "style",
      "message": "末尾の半角スペース",
      "suggested_fix": null
    }
  ]
}
```

| フィールド | 型 | 用途 |
| --- | --- | --- |
| `phase` / `iteration` | - | state JSON と紐付け |
| `overall` | string | `PASS`（BLOCK 0 件）/ `FAIL`（BLOCK ≥1 件） |
| `summary` | string | 1〜3 文の総評 |
| `findings[].severity` | string | `BLOCK` / `SUGGEST` / `NIT` |
| `findings[].path` | string | 対象ファイル |
| `findings[].line` | int / null | 該当行（任意） |
| `findings[].category` | string | `completeness` / `consistency` / `naming` / `security` / `performance` / `style` / `traceability` 等 |
| `findings[].message` | string | 指摘内容（日本語） |
| `findings[].suggested_fix` | string / null | 推奨修正（任意） |

### 重大度ガイドライン

| 重大度 | 定義 | fix 対象 | PASS 判定への影響 |
| --- | --- | --- | --- |
| `BLOCK` | 設計上の欠落・矛盾・要件未充足・セキュリティ重大 | ✅ 必修 | 1 件でも残ると `FAIL` |
| `SUGGEST` | 改善余地・冗長性・将来リスク | ✅ 修正対象 | 残存しても `PASS` |
| `NIT` | 表記揺れ・末尾空白・コメント文体 | ❌ 無視 | 無関係 |

## 6. orchestrator skill のロジック

各 `*-loop` skill は単一実行内で次のループを回す:

```
1. load-state: .skills-state/<phase>/state.json を読む（存在しなければ init-state.sh で生成）
2. 終了条件チェック:
   - state.passed == true                         → 「✅ PASS」サマリ表示 → exit
   - state.iteration > state.max_iterations       → escalate サマリ表示 → exit
   - state.escalated == true                      → 過去にエスカ済み → exit
3. state.stage に応じて分岐:
   ┌──────────────┬──────────────────────────────────────────────────────────┐
   │ produce      │ SlashCommand で /requirements-from-input 等を呼ぶ        │
   │              │ → advance-state.sh <phase> review                        │
   ├──────────────┼──────────────────────────────────────────────────────────┤
   │ review       │ SlashCommand で /review-<phase> を呼ぶ                   │
   │              │ → record-review.sh <phase> <review-json-path>            │
   │              │ → BLOCK == 0 ? passed=true → exit                        │
   │              │ → BLOCK > 0  ? advance-state.sh <phase> fix              │
   ├──────────────┼──────────────────────────────────────────────────────────┤
   │ fix          │ SlashCommand で /fix-<phase> を呼ぶ                      │
   │              │ → advance-state.sh <phase> review (iteration++)          │
   ├──────────────┼──────────────────────────────────────────────────────────┤
   │ done         │ 既に完了 → 完了サマリだけ表示 → exit                     │
   ├──────────────┼──────────────────────────────────────────────────────────┤
   │ escalate     │ 上限到達 → 未解決 BLOCK 一覧を表示 → exit               │
   └──────────────┴──────────────────────────────────────────────────────────┘
4. ループの先頭に戻る（state 再読み込み）
```

### orchestrator が `context: fork` しない理由

- ループ回数や直近の review 結果を会話内で保持しながら sub-skill 呼び出しを連鎖させる必要がある
- fork すると孫 fork 不可・状態の引き継ぎが煩雑

### sub-skill が `context: fork` する理由

- produce: 入力（前 phase の成果物パス）と出力（自 phase の成果物）が**ファイルで完結**するので、main 文脈に依存しない
- review: 前段 produce の「思考の道筋」が見えると評価が歪む。fork で**独立判定**を強制
- fix: 入力（review JSON）と出力（成果物修正）がファイル完結

## 7. 終了条件とエスカレーション

| 状態 | 動作 | 出力 |
| --- | --- | --- |
| 1〜3 回目の review で BLOCK == 0 | `state.passed = true`、`stage = done` | ✅ サマリ表示（iteration / 修正件数 / 残った SUGGEST 件数） |
| iteration が max_iterations を超過し BLOCK 残存 | `state.escalated = true`、`stage = escalate` | ❌ 未解決 BLOCK 一覧と発生 phase / iteration を表示。人手レビュー必須 |
| 任意の sub-skill が異常終了 | orchestrator が即停止 | ⚠️ 直近 state.json を表示し、ユーザーに判断を委ねる |

> **エスカレーション判定の所在**: PASS（BLOCK==0）/ escalate（BLOCK 残存かつ iteration ≥ max_iterations）の判定は `record-review.sh` に **一元化** している。`advance-state.sh` は stage 遷移と iteration++ のみを担当し、escalate 判定は行わない（判定が 2 箇所に分散することによる off-by-one を防ぐ）。
>
> **history への記録**: `advance-state.sh` は produce / fix 等の stage 完了を、`record-review.sh` は review 完了（block / suggest / nit 件数つき）と done / escalate を、それぞれ `state.history` に追記する。これにより review 結果も監査ログに残る。

## 8. 既存 agent との関係

11 個の agent はすべて **skill 群に責務を移管し、非推奨スタブ化**する。

| 旧 agent | 移管先 |
| --- | --- |
| requirements-author | `/requirements-from-input` + `/fix-requirements` |
| requirements-spec-designer | `/design-from-requirements` + `/fix-design` |
| springboot-backend-implementer | `/implement-from-issue` + `/fix-implementation`（内部で参照する設計指針） |
| react-frontend-implementer | 同上 |
| db-schema-implementer | 同上 |
| unit-test-engineer | `/implement-from-issue` 内の品質ゲート（Pattern 2 fan-out） |
| static-analysis-engineer | 同上 |
| e2e-test-engineer | 同上 |
| coverage-maximizer | `/fix-implementation`（カバレッジ不足を BLOCK として review が指摘） |
| failure-investigator | `/fix-implementation`（失敗解析は fix skill 内で実施） |
| issue-ticket-creator | `/create-issues-from-design`（既存）から呼ばれる役割で、skill に統合済み |

加えて、Agent Teams を前提にしていた skill も非推奨スタブ化する。

| 非推奨 skill | 後継 |
| --- | --- |
| `java-todo-team-bootstrap`（agent team 組成） | `*-loop` の skill 連鎖（Agent Teams 不使用） |
| `implement-from-design`（Issue を経ない直接実装） | `/create-issues-from-design` → `/implement-loop <ISSUE>` |

## 9. アンチパターン回避（記事準拠）

1. **全処理を SKILL.md に書かない** → state 操作は `_common/scripts/` のシェルスクリプトに分離
2. **フェーズ間の依存を明示する** → state.history に各 stage 完了タイムスタンプ（review は block 件数つき）を記録、orchestrator は前段成功を必ず確認。フェーズ採択は `approved.json`（approve-phase.sh）で機械的に確認
3. **状態管理をサボらない** → 各 stage 終了時に必ず state を書き戻し、orchestrator は冒頭で state を再読

## 10. .gitignore 追記推奨

`.skills-state/` はローカル作業状態のため、git には含めない:

```gitignore
.skills-state/
```

## 11. 人手採択ゲート（approved.json）

「採択前は次工程に進まない」という CLAUDE.md のルールを、AI の自己申告ではなくマーカーファイルで機械的に強制する。

- 採択: 要件・設計の各フェーズ完了後、**人手**で `bash .claude/skills/_common/scripts/approve-phase.sh <phase> <承認者名>` を実行し、`.skills-state/<phase>/approved.json`（`approved: true` / approver / approved_at / git_sha）を生成する。
- 後続 skill の前提条件: `design-from-requirements`（requirements 採択を要求）、`ui-brief-from-design` / `create-issues-from-design` / `implement-from-issue`（design 採択を要求）は、開始前に該当 `approved.json` の `approved == true` を Read で確認し、未採択なら中断する。
- 取消: 設計をやり直す場合は `approve-phase.sh <phase> --revoke` で `approved` を false に落とす。
- ループの `passed=true`（BLOCK==0 で自動）とは独立。BLOCK==0 はレビュー観点を満たしたことを意味するだけで、人手採択とは別の関門である。

## 12. 整合性の機械チェック

CI または手動で次を実行し、skill 連鎖の壊れを早期検出する。

- `bash .claude/skills/_common/scripts/check-skill-names.sh` — `*-loop` が SlashCommand で呼ぶ skill 名が、実在する skill（frontmatter `name:`）に解決できるか検証する。過去に implement-loop が `/review-implement`（実名 `review-implementation`）を呼んでループが起動しない不具合があったため、その再発を防ぐ。
