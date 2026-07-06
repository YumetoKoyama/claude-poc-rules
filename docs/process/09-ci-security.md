# CI/CD セキュリティ方針（RC-12）

（2026-07-02: 親 CLAUDE.md から PP-5/F-2 スリム化のため移設。内容は変更していない。親 CLAUDE.md「CI/CD セキュリティ方針」節が本ファイルを参照する）

- **`@claude` 自動修正系ワークフロー（`claude-fix-*`）の発火制限**: `author_association ∈ {OWNER, MEMBER, COLLABORATOR}` のコメント/イベントでのみ発火させる（外部の任意ユーザーによるプロンプトインジェクションを防ぐ）。Bash 許可・PAT scope は最小化する。
- **`pull_request_target` の回避**: フォーク PR のコードを書き込み権限つきで実行する `pull_request_target` トリガは原則使わない。必要な場合は信頼境界（author_association チェック・明示ラベル）を必ず併用する。
- **自動 Issue 起票ワークフロー（`create-issues-from-docs` 等）の制限**: 起票・後続トリガは `MEMBER` 以上のアクターに限定する。
- これらは CI 雛形（`rules/template` 相当）として固定し、`create-issues` / bootstrap で配布する（親 CLAUDE.md 単独記載では CI 非到達のため、雛形＝子へ配布される成果物に多重化する）。
- 関連: sub-skill（`fix-*`）の直接起動封じ・`allowed-tools` 明示（ノウハウ集 15 / CI-2）。
