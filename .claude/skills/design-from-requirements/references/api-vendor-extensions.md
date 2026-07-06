## YAML ベンダー拡張リファレンス（バックエンドコード自動生成）

以下のベンダー拡張は **バックエンドの `pojo.mustache` カスタムテンプレートが解釈**し、`mvn generate-sources` で Java アノテーションを自動付与する。**設計時に正しく設定しないと、バックエンド実装者が手動で後付けするか、制約が抜けたまま本番に出る**。

### マスク・非公開制御

フィールドの値をレスポンスから除外し、ログ (`toString()`) でもマスクする。以下のいずれかを付与する。

| YAML 記述 | 生成されるアノテーション | 使いどころ |
|---|---|---|
| `format: password` | `@JsonProperty(WRITE_ONLY)` | パスワード、ハッシュ値など |
| `writeOnly: true` | `@JsonProperty(WRITE_ONLY)` | レスポンス除外が必要な書き込み専用フィールド全般 |
| `x-sensitive: true` | `@JsonProperty(WRITE_ONLY)` | 電話番号・口座番号など PII だが `password`/`writeOnly` が意味的に不適切な場合 |

> `format: password` と `writeOnly: true` は意味が異なる（`password` はフォーマット指定、`writeOnly` は可視性制御）が、どちらも同じ保護効果を持つ。意味に合う方を選ぶ。

### Bean Validation アノテーション（`x-validate-*`）

OpenAPI 標準キーワード（`minimum`, `maximum`, `minLength`, `maxLength`, `pattern`）で表現できない制約に使う。

| YAML キー | 生成されるアノテーション | 使いどころ |
|---|---|---|
| `x-validate-future: true` | `@Future` | 日時フィールドが未来であること |
| `x-validate-future-or-present: true` | `@FutureOrPresent` | 現在以降の日時 |
| `x-validate-past: true` | `@Past` | 日時フィールドが過去であること |
| `x-validate-past-or-present: true` | `@PastOrPresent` | 現在以前の日時 |
| `x-validate-not-blank: true` | `@NotBlank` | 空白のみを弾く（`required` + `minLength: 1` では空白文字列が通る） |
| `x-validate-positive: true` | `@Positive` | 正の数（0 を弾く） |
| `x-validate-positive-or-zero: true` | `@PositiveOrZero` | 0 以上の数 |
| `x-validate-negative: true` | `@Negative` | 負の数 |

> **注意**: これらで表現できない業務ルール（「現在から 2 時間以上先」などの相対条件、フィールド間の相関制約）は `x-validate-*` で対処できない。設計書の業務ルール（BR-XXX）に明記し、バックエンドの UseCase Validator で実装する。

### `format: email`（標準、ベンダー拡張不要）

`format: email` は OpenAPI 標準で、OpenAPI Generator が `@Email` を自動付与する。ベンダー拡張は不要。

### 機密フィールドの YAML 記述例

```yaml
components:
  schemas:
    LoginRequest:
      type: object
      required: [email, password]
      properties:
        email:
          type: string
          format: email                      # @Email を自動生成
        password:
          type: string
          format: password                   # @JsonProperty(WRITE_ONLY) + toString() マスク
          minLength: 8
    UserProfileResponse:
      type: object
      properties:
        userId: { type: integer, format: int64 }
        email: { type: string, format: email }
        phoneNumber:
          type: string
          x-sensitive: true                  # PII: @JsonProperty(WRITE_ONLY) + toString() マスク
          description: "電話番号（応答には含まれない）"
        internalToken:
          type: string
          writeOnly: true                    # @JsonProperty(WRITE_ONLY) + toString() マスク
          description: "書き込み専用（レスポンスに含まれない）"
```
