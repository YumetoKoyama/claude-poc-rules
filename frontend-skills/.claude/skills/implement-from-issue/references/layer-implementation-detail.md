# 実装レイヤ別詳細（各レイヤ完了時の中間サマリ書き出し）

implement-from-issue（frontend-skills 系統）本文から 2026-07-02 に PP-5 分解で外出し。本文の該当手順から参照される。

<!-- rules 改善（S7）: 各レイヤ完了時の中間サマリ書き出し（コンテキスト溢れ対策） -->
#### 4.1. 各レイヤ完了時の中間サマリ書き出し（S7・コンテキスト溢れ対策）

画面 / フック / サービス（API クライアント）の各まとまり完了時に、次のまとまりが参照すべき確定情報を**中間サマリファイル**（own リポジトリ直下 `.skills-state/implement/impl-summary-$ARGUMENTS.md`・gitignore 対象）に追記する。長い実装でコンテキストが溢れても、後続はこのファイルを Read して整合を取れる。

- サービス層完了時: 呼び出す **operationId・Request/Response 型名・主要フィールド名**
- store/フック完了時: 公開する **状態キー・アクション名**
- 画面コンポーネント完了時: **コンポーネント名・呼び出す operationId・利用するレスポンスフィールド**

```bash
mkdir -p .skills-state/implement
# 例（サービス層完了時）:
cat >> .skills-state/implement/impl-summary-$ARGUMENTS.md << 'EOS'
## サービス層
- service: <名>（operationId: <id>, Response 型: <名>, 使用フィールド: <列挙>）
EOS
```
