## IF定義.md

```markdown
# IF定義

## 外部インターフェース

| IF名 | 種別 | エンドポイント / トピック | 認証方式 | 説明 |
|-----|------|------------------------|---------|------|
|     |      |                        |         |      |

### [IF名] 詳細

- 呼び出し方向:（本システム → 外部 / 外部 → 本システム）
- プロトコル:
- リクエスト仕様:
- レスポンス仕様:
- エラー処理方針:

## 内部インターフェース

| IF名 | 呼び出し元 | 呼び出し先 | 説明 |
|-----|----------|----------|------|
|     |          |          |      |
```

---

## DB定義.md（DB 全体方針）

```markdown
# DB 設計（全体方針）

## 全体方針

- 想定 RDB:
- 文字コード / 照合順序:
- タイムゾーン方針:
- 命名規約（テーブル / カラム / インデックス / 外部キー）:

## テーブル一覧

| テーブル名 | Entity クラス名 | 説明 | 詳細ファイル |
|----------|---------------|------|------------|
| users    | User          |      | `tables/users.md` |
| items    | Item          |      | `tables/items.md` |
| orders   | Order         |      | `tables/orders.md` |

## 全体 ER 図

> Mermaid `erDiagram` を必ず使用すること。テーブルごとの詳細列定義は各 `tables/[テーブル名].md` に置く。

\`\`\`mermaid
erDiagram
    USERS ||--o{ ORDERS : "places"
    ORDERS ||--|{ ORDER_ITEMS : "contains"
    ITEMS  ||--o{ ORDER_ITEMS : "is_referenced_by"

    USERS {
      bigint id PK
      varchar email
    }
    ITEMS {
      bigint id PK
      varchar name
      int    price
    }
    ORDERS {
      bigint id PK
      bigint user_id FK
      datetime ordered_at
    }
    ORDER_ITEMS {
      bigint id PK
      bigint order_id FK
      bigint item_id FK
      int    quantity
    }
\`\`\`

## migration 方針

- ツール:（Flyway / Liquibase など）
- ファイル命名規約:
- 既存データ移行方針:

## index 方針（全体ガイドライン）

| 観点 | 方針 |
|------|------|
| 主キー | 単一サロゲートキー（bigint） |
| 外部キー | 関連先カラムへ自動採番 index |
| 検索系 |  |
```

---

## tables/[テーブル名].md

ファイル名規約: DB 物理名と同じ snake_case 英語で揃える（例: `tables/users.md`、`tables/order_items.md`）。

```markdown
# テーブル定義: users

- 説明:
- Entity クラス名: User
- 関連要件: `docs/requirements/functional/[機能名].md`

## カラム定義

> **共通カラム（更新を伴う全テーブルに付与する）**: 楽観ロックの基盤として `version` を持たせる。参照専用・マスタ等で楽観ロックが不要な場合は「排他制御」セクションにその理由を明記したうえで省略してよい。
>
> | カラム名 | 型 | NOT NULL | デフォルト | 説明 |
> |---------|----|---------|----------|------|
> | version | INTEGER | YES | 0 | 楽観ロック用バージョン（JPA `@Version`） |
> | created_at | DATETIME | YES | CURRENT_TIMESTAMP | 作成日時 |
> | updated_at | DATETIME | YES | CURRENT_TIMESTAMP | 更新日時 |

| カラム名 | 型 | NOT NULL | デフォルト | 説明 |
|---------|----|---------|----------|------|
| id      | BIGINT | YES | AUTO_INCREMENT | 主キー |
| email   | VARCHAR(255) | YES |  | ログインメールアドレス（ユニーク） |
| version | INTEGER | YES | 0 | 楽観ロック用バージョン（@Version） |
| created_at | DATETIME | YES | CURRENT_TIMESTAMP | 作成日時 |
| updated_at | DATETIME | YES | CURRENT_TIMESTAMP | 更新日時 |

## 制約

| 制約種別 | 対象カラム | 説明 |
|--------|---------|------|
| PRIMARY KEY | id |  |
| UNIQUE | email |  |

## インデックス

| インデックス名 | 対象カラム | 種別 | 理由 |
|------------|---------|------|------|
| idx_users_email | email | UNIQUE | ログイン検索用 |

## 排他制御

> 状態遷移・先着・上限・二重防止・カウンタ更新を持つテーブルは、楽観ロック（`version` カラム＋ `@Version`）または悲観ロック（`SELECT ... FOR UPDATE`）の採用方式と根拠を必ず記述する。排他制御が不要なテーブル（参照のみ・マスタ等）は「排他制御不要（理由: ...）」と明記する。詳細な使い分け基準・デッドロック防止方針は `共通部品設計.md` の正典に従う。

| 操作 | 方式 | 根拠 |
|------|------|------|
| （例）アカウント情報の同時編集 | 楽観ロック（version カラム / @Version） | 競合頻度が低く、ユーザーに再試行（409 → リトライ）を許容できる |
| （例）応募枠の引き当て | 悲観ロック（SELECT FOR UPDATE）＋一意制約 | 競合頻度が高く、二重引き当て・上限超過が業務上致命的 |

## リレーション

| 種別 | 相手テーブル | カラム | カーディナリティ | 削除時挙動 |
|------|----------|------|-------------|----------|
| 1:N  | orders   | orders.user_id | 1 ユーザー : 多数注文 | RESTRICT |

## 部分 ER 図（このテーブル + 周辺）

> 自テーブルと、外部キー / 参照されるテーブルを含めて Mermaid で図示する。

\`\`\`mermaid
erDiagram
    USERS ||--o{ ORDERS : "places"

    USERS {
      bigint id PK
      varchar email
      datetime created_at
    }
    ORDERS {
      bigint id PK
      bigint user_id FK
      datetime ordered_at
    }
\`\`\`
```
