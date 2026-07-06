# 技術スタックの正典と確定ルール（詳細）

（2026-07-02: 親 CLAUDE.md「技術スタックの正典と確定ルール」節から PP-5/F-2 スリム化のため詳細を移設。内容は変更していない。要点とハードゲートは親 CLAUDE.md に残置）

技術スタックは要件で**人間が指定する**。Claude は既定値で自動補完しない。未指定・未確定のまま設計・製造フェーズに進まない（**ハードゲート**）。

- **確定したスタックの正典は対象子リポジトリの `.claude/rules/` に集約する**。CLAUDE.md・設計書（`docs/design/方式設計.md` 等）・スキルでは、フレームワーク名・ライブラリ名・バージョンを**再掲しない**。必要な箇所では各子の `.claude/rules/` を参照する（二重管理の禁止）。
  - フロントエンド: `claude-poc-frontend/.claude/rules/frontend-*.md`
  - バックエンド: `claude-poc-backend/.claude/rules/backend-*.md`（実装規約。ビルド / DB / テスト / 静的解析 / カバレッジ閾値などのスタック確定値も、人間がここに追記して確定する）
  - リポジトリ構成・E2E の所在などの横断決定: `docs/process/リポジトリ構成と移行計画.md` に記録する
- **未指定時の挙動**: 採用技術が未確定のまま設計フェーズ（`design-from-requirements`）以降に進まない。対象子の `.claude/rules/` 上に「要確定」項目が残る間は中断し、人間に指定を求める。既定値による自動決定は禁止する。
- **機械的強制**: 確定状況は各子の `.claude/rules/[fe|be]*-00-stack.md`（技術スタック確定表）を正典とし、`design-loop` / `design-from-requirements` は開始前に `.claude/skills/_common/scripts/check-stack-decided.sh` を実行する。`要確定` が残る場合・確定表が存在しない場合（未記載 = 要確定）は exit 1 で設計着手をブロックし、未確定項目の一覧を人間に提示する。
- **矛盾時の優先順位**: 複数文書・複数選択肢で技術が食い違う場合は、**frontend ルール（`claude-poc-frontend/.claude/rules/frontend-*.md`）を最優先（正）** とし、他（CLAUDE.md の旧記述・設計書・スキル）はそれに合わせる。
