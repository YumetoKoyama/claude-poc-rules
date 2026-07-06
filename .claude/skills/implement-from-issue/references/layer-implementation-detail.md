# 実装レイヤ別詳細（DB / バックエンド / フロントエンド）

implement-from-issue 本文から 2026-07-02 に PP-5 分解で外出し。本文の該当手順から参照される。

## 1. DB

   - **排他制御の実装（ADD-4）**: テーブル定義に `version` 列（楽観ロック用）がある場合は Entity に `@Version` を付与する。`共通部品設計.md` / `tables/*.md` で**悲観ロック**が指定されたテーブルは、対応する Repository のクエリに `@Lock(LockModeType.PESSIMISTIC_WRITE)` を付与する。状態遷移・先着・上限・二重防止は read-modify-write ではなく **DB 一意制約 / 条件付き UPDATE / 行ロック**で保証する。

## 2. バックエンド

   - **並行制御の例外マッピング（RC-01）**: `OptimisticLockException` / `DataIntegrityViolationException` を `GlobalExceptionHandler` で **409 Conflict** にマッピングする。
   - **セキュリティ実装は設計値と完全一致（RC-05 / RC-07）**: 認証・認可・CORS・パスワードハッシュ等は `docs/design/セキュリティ設計.md` の定義値（JWT 有効期限／CORS 許可オリジン／BCrypt ラウンド数（≥12）／ログイン試行制限／時刻は `Clock` 注入／メール送信は `@Transactional` 外）を参照し、実装コード・設定ファイルの値と**完全に一致**させる。**設計値と異なる値が必要な場合は ESCALATE**（実装で勝手に決めず設計変更として人間に戻す）。

## 3. フロントエンド

   - **FE 実装規約は frontend ルールを正典とする（G-01/02/15）**: 着手前に対象 repo の `.claude/rules/frontend-*.md`（ディレクトリ構成・状態管理・API 連携・ルーティング・テスト命名）を必ず Read し、その規約に従う。CLAUDE.md・本スキルは FW 固有の構成（旧 Presentational/Container 分割・`src/api/` 集約 等）を**規定しない**。frontend ルールと矛盾する旧記述には従わず、矛盾時は frontend ルールを正とする。
   - **別リポジトリ運用（G-06/07）**: FE と BE は別リポジトリのため、ブランチ・PR・品質ゲートのレポート判定は **実行中の repo 単位**で行う（同一作業ツリーに FE/BE のレポートは同居しない）。1 Issue が両 repo にまたがる場合は repo ごとに PR を作成して相互リンクする。
   - **データ連鎖の遵守（dead-field 防止・2026-06-12）**: 画面で表示・業務判定に使うフィールドは、対応する API レスポンス型のフィールドから取得する。レスポンスに無いからといって空文字・固定値・`|| 'デフォルト'` で握り潰さない。供給元フィールドが API に無い場合は ESCALATE（設計の API レスポンス追加が必要）。

## 4.1 各レイヤ完了時の中間サマリ書き出し（S7・コンテキスト溢れ対策）

DB / BE / FE の各レイヤ完了時に、次レイヤが参照すべき確定情報を**中間サマリファイル**（own リポジトリ直下 `.skills-state/implement/impl-summary-$ARGUMENTS.md`・gitignore 対象）に追記する。長い実装でコンテキストが溢れても、次レイヤはこのファイルを Read して整合を取れる。

- DB 完了時: 作成した **Entity 名・テーブル名・主キー・`version` 列の有無・一意制約**
- BE 完了時: 実装した **API パス・operationId・Request/Response DTO 名・主要フィールド名**
- FE 完了時: 作成した **画面コンポーネント名・呼び出す operationId・利用するレスポンスフィールド**

```bash
mkdir -p .skills-state/implement
# 例（DB レイヤ完了時）:
cat >> .skills-state/implement/impl-summary-$ARGUMENTS.md << 'EOS'
## DB レイヤ
- Entity: <名>（table: <名>, PK: <列>, version: あり/なし, unique: <制約>）
EOS
```
