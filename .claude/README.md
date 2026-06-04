# React + Spring Boot Web アプリ開発向け Claude 設定

このリポジトリには、フロントエンド（React / TypeScript）と バックエンド（Spring Boot REST API）、RDB、単体テスト、カバレッジ改善、静的解析、Playwright MCP を使った E2E 自動化を含む Web アプリ開発向けの再利用可能な Claude Code 設定が含まれています。

## アーキテクチャ

本プロジェクトは **skill オーケストレーション**（[docs/architecture/skill-orchestration.md](../docs/architecture/skill-orchestration.md)）で構成されています。
agent ベースの構成は廃止しました（Agent Teams は experimental のため）。

各フェーズに `*-loop` orchestrator skill があり、`produce → review → fix → review` を最大 3 回まで自動で回します（Pattern 4: Iterative Loop）。

## 含まれているもの

- プロジェクト共通指示: [../CLAUDE.md](../CLAUDE.md)
- 設計ドキュメント: [../docs/architecture/skill-orchestration.md](../docs/architecture/skill-orchestration.md)
- skill 定義: [.claude/skills](skills)
- 共通スクリプト: [.claude/skills/_common/scripts/](skills/_common/scripts)
- 実験的 agent team 有効化: [settings.json](settings.json)（互換用に残置、未使用）

## 推奨フロー（GitHub Issues 連携）

```
1. /requirements-loop <要件素材ファイル>
   ├─ produce → /requirements-from-input
   ├─ review  → /review-requirements (BLOCK/SUGGEST/NIT JSON 出力)
   └─ fix     → /fix-requirements (BLOCK + SUGGEST のみ反映)
       (BLOCK == 0 で PASS / 3 回反復で ESCALATE)

2. 人手レビュー → 要件定義の採択

3. /design-loop [docs/requirements/]
   ├─ produce → /design-from-requirements
   ├─ review  → /review-design
   └─ fix     → /fix-design

4. 人手レビュー → 設計書の採択

5. /create-issues-from-design [docs/design/]
   └─ GitHub Issue を画面・API・IF・テーブル単位で起票

6. /implement-loop <ISSUE-NUMBER>
   ├─ produce → /implement-from-issue (内部で UT/静的解析/E2E を Pattern 2 並列)
   ├─ review  → /review-implementation
   └─ fix     → /fix-implementation (同じ feature ブランチへ追加コミット)

7. 人手レビュー → PR レビュー・マージ
```

## skill 一覧

### orchestrator（context: fork なし）

| skill | 役割 | 引数 |
| --- | --- | --- |
| `/requirements-loop` | 要件定義フェーズの反復ループを管理 | `<要件素材ファイル>` |
| `/design-loop` | 設計フェーズの反復ループを管理 | `[docs/requirements/]` |
| `/implement-loop` | 実装フェーズの反復ループを管理 | `<ISSUE-NUMBER>` |

### produce（既存）

| skill | 役割 |
| --- | --- |
| `/requirements-from-input` | 要件素材から `docs/requirements/` 一式を生成 |
| `/design-from-requirements` | 採択済み要件定義から `docs/design/` 一式を生成 |
| `/implement-from-issue` | GitHub Issue から実装・品質ゲート（並列）・PR 作成 |
| `/create-issues-from-design` | 採択済み設計書から GitHub Issue を起票 |

### review（context: fork あり）

| skill | 役割 |
| --- | --- |
| `/review-requirements` | 要件定義をレビューし review JSON を生成 |
| `/review-design` | 設計書をレビューし review JSON を生成 |
| `/review-implementation` | 実装差分と品質ゲート結果をレビューし review JSON を生成 |

### fix（context: fork あり）

| skill | 役割 |
| --- | --- |
| `/fix-requirements` | review JSON の BLOCK + SUGGEST を要件定義に反映 |
| `/fix-design` | review JSON の BLOCK + SUGGEST を設計書に反映 |
| `/fix-implementation` | review JSON の BLOCK + SUGGEST をコード/テストに反映し追加コミット |

### 補助（既存）

| skill | 役割 |
| --- | --- |
| `/implement-from-design` | 設計書から直接実装（Issue を経由しないフロー） |
| `/unit-test-from-design` | 設計書から単体テストだけを追加 |
| `/coverage-to-100` | カバレッジ未到達部分を補完 |
| `/static-analysis-remediation` | 静的解析の指摘を修正 |
| `/e2e-from-design` | 設計書から E2E シナリオを作成 |
| `/java-web-team-bootstrap` | （旧 agent team 設定。skill 移行で実質未使用） |

## 状態管理

各 phase の orchestrator は `.skills-state/<phase>/state.json` に状態を保持します（gitignore 対象）。

```
.skills-state/
├── requirements/
│   ├── state.json
│   ├── round-1-review.json
│   └── round-2-review.json
├── design/
└── implement/
```

state JSON / review JSON のスキーマは [docs/architecture/skill-orchestration.md](../docs/architecture/skill-orchestration.md) を参照。

## 補足

- 全ての skill 本文は日本語で書かれており、生成物（要件定義書・設計書・コメント等）も日本語で出力されます。
- E2E は Playwright MCP を前提としています。利用時は Claude セッション側で Playwright MCP が利用可能であることを確認してください。
- GitHub Issues / PR / Projects の操作は **`gh` CLI に一本化**（`.mcp.json` は廃止）。認証は `GH_TOKEN`（docker-compose が PAT をマッピング。classic PAT: `repo` + `project` + 必要に応じ `read:org`）。

## Playwright MCP を前提にした E2E 実行プロンプト例

- /e2e-from-design docs/design/シナリオ戦略.md
- /e2e-from-design docs/design/シナリオ戦略.md を使って、一覧表示・登録・入力エラー表示の E2E シナリオを Playwright MCP で作成してください。
- /e2e-from-design docs/design/シナリオ戦略.md を使って、登録から更新・削除までの一連のユーザーフローを Playwright MCP で検証してください。

## E2E 失敗時の investigation フロー

1. まず失敗したシナリオ名、URL、画面操作、期待結果、実結果を要約させる。
2. Playwright MCP で失敗直前と失敗時点の画面状態、DOM、表示メッセージを取り直させる。
3. セレクタ不整合、画面描画遅延、初期データ不整合、バックエンドエラーのどれが最有力か仮説を 1 つに絞らせる。
4. 同じシナリオを最小条件で再実行し、再現性を確認させる。
5. 必要に応じてサーバーログ、HTTP 応答、永続化結果を確認し、UI 問題かバックエンド問題かを切り分ける。
6. 原因確定後は、テスト修正で直すべきか、アプリケーション修正で直すべきかを明示させる。
7. 修正後は同じシナリオを再実行し、関連する近接シナリオまで再確認する。
