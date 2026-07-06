## api/[リソース名].yaml

ファイル名規約: リソース名の kebab-case 英語（例: `items.yaml`, `users.yaml`, `applications.yaml`）。ファイル名は URL パスのリソース名と一致させ、同一リソースに属する全 HTTP メソッド・パスを 1 ファイル内の `paths:` 配下に集約する。

```yaml
openapi: 3.1.0
info:
  title: アイテム API
  version: 0.1.0
  description: |
    関連要件: docs/requirements/functional/アイテム登録.md, docs/requirements/functional/アイテム検索.md
    関連画面: SCR-003 アイテム一覧, SCR-004 アイテム登録, SCR-005 アイテム詳細
paths:
  /api/items:
    get:
      operationId: listItems
      summary: アイテム一覧を取得する
      description: |
        業務ルール: BR-009
        受け入れ条件: AC-100
      security:
        - bearerAuth: []
      parameters:
        - $ref: "./_common.yaml#/components/parameters/PageParam"
        - $ref: "./_common.yaml#/components/parameters/PageSizeParam"
      responses:
        "200":
          description: 一覧取得成功
          content:
            application/json:
              schema:
                type: object
                properties:
                  items:
                    type: array
                    items:
                      $ref: "#/components/schemas/ItemResponse"
                  total: { type: integer }
        "401":
          $ref: "./_common.yaml#/components/responses/Unauthorized"
        "500":
          $ref: "./_common.yaml#/components/responses/InternalServerError"
    post:
      operationId: createItem
      summary: アイテムを登録する
      description: |
        業務ルール: BR-010, BR-011
        受け入れ条件: AC-001, AC-101
      security:
        - bearerAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/ItemCreateRequest"
      responses:
        "201":
          description: 登録成功
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/ItemResponse"
        "400":
          $ref: "./_common.yaml#/components/responses/BadRequest"
        "401":
          $ref: "./_common.yaml#/components/responses/Unauthorized"
        "500":
          $ref: "./_common.yaml#/components/responses/InternalServerError"
  /api/items/{id}:
    get:
      operationId: getItemById
      summary: アイテム詳細を取得する
      description: |
        受け入れ条件: AC-102
      security:
        - bearerAuth: []
      parameters:
        - name: id
          in: path
          required: true
          schema: { type: integer, format: int64 }
      responses:
        "200":
          description: 取得成功
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/ItemResponse"
        "404":
          $ref: "./_common.yaml#/components/responses/NotFound"
    patch:
      operationId: updateItem
      summary: アイテムを更新する
      security:
        - bearerAuth: []
      parameters:
        - name: id
          in: path
          required: true
          schema: { type: integer, format: int64 }
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/ItemUpdateRequest"
      responses:
        "200":
          description: 更新成功
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/ItemResponse"
        "400":
          $ref: "./_common.yaml#/components/responses/BadRequest"
        "404":
          $ref: "./_common.yaml#/components/responses/NotFound"
    delete:
      operationId: deleteItem
      summary: アイテムを削除する
      security:
        - bearerAuth: []
      parameters:
        - name: id
          in: path
          required: true
          schema: { type: integer, format: int64 }
      responses:
        "204":
          description: 削除成功
        "404":
          $ref: "./_common.yaml#/components/responses/NotFound"
components:
  schemas:
    ItemCreateRequest:
      type: object
      required: [name, price, scheduledAt]
      properties:
        name:
          type: string
          minLength: 1
          maxLength: 100
          x-validate-not-blank: true        # @NotBlank: 空白のみの文字列を弾く
          pattern: '^[^<>]*$'
          description: "プレーンテキスト。HTMLタグ不可。"
        price:
          type: integer
          minimum: 1
          x-validate-positive: true         # @Positive: 0 を弾く（minimum:1 だけでは @Positive が付かないため併記）
        scheduledAt:
          type: string
          format: date-time
          x-validate-future: true           # @Future: 未来日時のみ受け付け
          description: "予定日時（未来日時のみ受付）"
        description:
          type: string
          maxLength: 1000
          pattern: '^[^<>]*$'
          description: "プレーンテキスト。HTMLタグ不可。"
    ItemUpdateRequest:
      type: object
      properties:
        name: { type: string, minLength: 1, maxLength: 100, x-validate-not-blank: true, pattern: '^[^<>]*$', description: "プレーンテキスト。HTMLタグ不可。" }
        price: { type: integer, minimum: 1, x-validate-positive: true }
        description: { type: string, maxLength: 1000, pattern: '^[^<>]*$', description: "プレーンテキスト。HTMLタグ不可。" }
    ItemResponse:
      type: object
      properties:
        id: { type: integer, format: int64 }
        name: { type: string }
        price: { type: integer }
        description: { type: string }
        createdAt: { type: string, format: date-time }
```

ベンダー拡張（機密フィールド・Bean Validation）の対応表と例は [api-vendor-extensions.md](api-vendor-extensions.md) を参照。

### YAML 構造の指針

- **1 ファイル = 1 リソース**: 同じリソース（URL パスの第一階層、例: `/api/items` 系）に属する全 HTTP メソッド・サブパス（`/api/items/{id}` 等）を同一 YAML の `paths:` 配下に集約する。
- ファイル名は URL のリソース名と対応させる（例: `items.yaml` → `/api/items` 系、`jobs.yaml` → `/api/jobs` 系、`applications.yaml` → `/api/jobs/{jobId}/applications` も含めて応募リソース観点で `applications.yaml` に集約）。
- リソースが大きく独立性が高い場合（例: `/api/auth/*`）は別ファイルに切り出して良い（`auth.yaml`）。
- 各 `operationId` は **camelCase** で命名し、後段のコード生成と整合させる（例: `listItems`, `createItem`, `getItemById`, `updateItem`, `deleteItem`）。
- 設計上の Controller / Service / Repository の責務分担、ログ要件、業務ルールの参照などは、各 operation の `description` / `summary` フィールドに自然文で必ず含めること。
- 各 YAML の冒頭 `info.description` で、関連要件ファイル・関連画面 ID・関連業務ルール ID を明示する。
- **XSS対策（必須）**: 要件で「プレーンテキスト」と定義された全文字列フィールドには `pattern: '^[^<>]*$'` と `description: "プレーンテキスト。HTMLタグ不可。"` を必ず付与する。リッチHTMLを許可するフィールドは要件書に明記された場合のみ例外とし、その場合も許可タグのallowlistをdescriptionに記載する。この制約がバックエンドの `@Pattern` バリデーションの根拠となる。
- **ベンダー拡張の付与漏れチェック（必須）**: YAML を作成・更新するたびに、以下のフィールドにベンダー拡張が付いているか確認する。
  - パスワード・ハッシュ・トークン・PII（電話番号・口座番号等）フィールド → `format: password` / `writeOnly: true` / `x-sensitive: true` のいずれか
  - 日時フィールドで「未来のみ」「過去のみ」などの制約がある → `x-validate-future: true` 等
  - 整数フィールドで「正の数」の業務制約がある → `x-validate-positive: true` 等
  - 文字列 `required` フィールドで「空白のみ禁止」の意図がある → `x-validate-not-blank: true`
  ベンダー拡張の付与漏れは、バックエンドの自動生成アノテーションが欠落し、セキュリティ・バリデーションの抜けに直結する。
