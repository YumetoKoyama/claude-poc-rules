# 横断 AI ルール（正典の構成・共通原則）

本リポジトリ（claude-poc-rules）は 6 リポジトリ構成の親（アンブレラ）であり、本ファイルは全リポジトリ横断のルールの正典である。

## 正典の二層構成

| 正典 | 置き場所 | 内容 |
|---|---|---|
| 開発フロー・横断ルール | 親 CLAUDE.md・親 rules/ | フェーズ順序・採択ゲート・ID/命名規約・正典保護 |
| フロントエンド技術ルール | claude-poc-frontend/.claude/rules/frontend-*.md | FW・構成・状態管理・テスト規約（矛盾時の最優先＝正） |
| バックエンド技術ルール | claude-poc-backend/.claude/rules/backend-*.md | アーキテクチャ・レイヤー・スタック確定値 |
| バッチ／E2E 技術ルール | claude-poc-batch / claude-poc-e2e の .claude/rules/ | 未作成（作成は人間。E2E は凍結中） |

- 技術スタックの確定値は**各子の `.claude/rules/` にのみ**記載する（親 CLAUDE.md・設計書・スキルは再掲せず参照する）。
- 親から起動したセッション・スキルは、子の rules を自動読み込みできないため、**対象リポジトリの `.claude/rules/` を必ず Read してから作業する**。

## 採択ゲート（人間の明示アクション）

- **要件定義・設計書の採択 = docs リポジトリ（claude-poc-docs）の `main` への PR マージ**。人間のレビュー・マージが採択行為であり、PR が証跡となる（前提: docs の `main` に branch protection）。
- **実装の開始 = 人間が対象 Issue に `@claude` とコメントすること**。Claude・skill が自らコメント・マージして起動してはならない。
- ローカル起動時は、入力ドキュメントが docs の `main` にマージ済みであることを確認し、未マージなら中断して人手レビュー・マージを依頼する。

## ID・命名の共通原則

- ID は「英字プレフィックス + 3 桁ゼロ埋め連番」（例: SCR-001、UC-001）。個別の ID 体系の定義は親 CLAUDE.md を正典とする。
- ID・略号を導入するドキュメントは冒頭付近に凡例（略号一覧表）を必ず置き、新規略号追加時に凡例も更新する。

## 正典の保護

- 親 `rules/`・親 CLAUDE.md・各子の `.claude/rules/` は Claude 実行中の編集を禁止する（`.claude/hooks/protect-canon.sh` が `(^|/)rules/` と `CLAUDE.md` をブロック。子の `.claude/rules/` もパターンに合致し保護される）。
- 変更は人手で行う。Claude に依頼する場合のみ `ALLOW_RULES_EDIT=1` のセッションで行う。
- スキルの自動実行はフラグを立てないため常にブロックされ、ルール書き換えで品質ゲートは通せない。
