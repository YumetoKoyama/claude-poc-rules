## api/_common.yaml

```yaml
openapi: 3.1.0
info:
  title: 共通スキーマ
  version: 0.1.0
  description: |
    全 API で共有する schema / response / parameter / security scheme を定義する。
    各エンドポイント YAML から $ref で参照する。
components:
  schemas:
    ErrorResponse:
      type: object
      required: [code, message]
      properties:
        code:
          type: string
          description: アプリケーション定義のエラーコード
        message:
          type: string
          description: ユーザー向けエラーメッセージ
        details:
          type: array
          items:
            type: object
            properties:
              field: { type: string }
              reason: { type: string }
    PageMeta:
      type: object
      properties:
        page: { type: integer, minimum: 1 }
        size: { type: integer, minimum: 1 }
        totalElements: { type: integer, minimum: 0 }
        totalPages: { type: integer, minimum: 0 }
  parameters:
    PageParam:
      name: page
      in: query
      required: false
      schema: { type: integer, minimum: 1, default: 1 }
    SizeParam:
      name: size
      in: query
      required: false
      schema: { type: integer, minimum: 1, maximum: 100, default: 20 }
  responses:
    BadRequest:
      description: バリデーションエラー
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/ErrorResponse"
    Unauthorized:
      description: 認証エラー
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/ErrorResponse"
    NotFound:
      description: リソース未存在
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/ErrorResponse"
    InternalServerError:
      description: サーバーエラー
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/ErrorResponse"
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
```
