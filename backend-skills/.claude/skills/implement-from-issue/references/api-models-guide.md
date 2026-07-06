# バックエンド API モデル生成ガイド

OpenAPI 3.1 YAML から Java DTO クラスを生成し、実装で使用する手順。
フロントエンドの `references/api-client-guide.md` に対応するバックエンド版。

## 生成の仕組み

`pom.xml` の `openapi-generator-maven-plugin` (v7.13.0) が `docs/design/api/*.yaml` を読み込み、
`target/generated-sources/openapi/com/example/logisticsmatching/generated/openapi/` に Java クラスを生成する。
出力先はコンパイルソースルートに自動追加されるため、`mvn compile` で即利用できる。

## 実行手順

### 生成スクリプトを使う（推奨）

```bash
# プロジェクトルートから実行
bash scripts/gen-api-models.sh
```

- `pom.xml` に登録済みの `openapi-gen-*` 実行エントリを順番に処理してモデルを生成する（YAML の自動検出はしない）
- 出力先 `target/generated-sources/openapi/` に `.java` ファイル数を報告する
- YAML ディレクトリを変えたい場合は `OPENAPI_SPEC_DIR` 環境変数で指定する
- docs リポジトリで YAML を追加・削除・リネームした場合は、先に `implement-from-issue` 手順 2.6 で `pom.xml` の `openapi-gen-*` エントリを同期すること

### Maven を直接呼ぶ場合

```bash
# Linux / Mac
mvn generate-sources -Dopenapi.spec.basedir="$(pwd)/../claude-poc-docs/docs/design/api"

# Git Bash on Windows（cygpath でパス変換が必要）
mvn generate-sources -Dopenapi.spec.basedir="$(cygpath -m "$(pwd)/../claude-poc-docs/docs/design/api")"
```

## 生成クラスの使い方

### パッケージ

```java
import com.example.logisticsmatching.generated.openapi.*;
```

### Controller での利用例

```java
@PostMapping
public ResponseEntity<JobResponse> createJob(
    @Valid @RequestBody JobCreateRequest request) {
    // ...
}
```

### 手動 DTO との使い分け

| ケース | 使うクラス |
|---|---|
| OpenAPI で定義済みのリクエスト/レスポンス | 生成クラス（`generated.openapi.*`） |
| DB エンティティ | 手書き `@Entity` クラス |
| OpenAPI 未定義の内部 DTO | 手書き `dto.*` クラス |

手動 DTO との重複定義は避ける。OpenAPI 定義があれば生成クラスを優先する。

## いつ再生成するか

以下のいずれかに該当する場合、実装前に再生成する:

- `target/generated-sources/openapi/` が存在しない
- `docs/design/api/*.yaml` に変更があった
- コンパイルエラーが `generated.openapi` パッケージから出ている

```bash
# 存在確認
ls target/generated-sources/openapi/src/main/java/com/example/logisticsmatching/generated/openapi/ 2>/dev/null \
  && echo "生成済み" || echo "要生成"
```

## YAML ベンダー拡張と自動生成される制約

`pojo.mustache` カスタムテンプレートにより、YAML に以下のベンダー拡張を記述すると
**再生成するだけで** Java アノテーションが自動付与される。
設計者（YAML 作成者）は該当するフィールドに必ずこれらを付与すること。

### マスク・非公開制御（`@JsonProperty(WRITE_ONLY)` + `toString()` マスク）

以下のいずれかを付与すると、getter に `@JsonProperty(access = WRITE_ONLY)` が付き、
`toString()` で値が `[MASKED]` に置き換えられる（ログ漏洩防止 R-SEC-050、R-SEC-111）。

| YAML 記述 | 対象の例 |
|---|---|
| `format: password` | パスワード、ハッシュ値 |
| `writeOnly: true` | 書込専用フィールド（レスポンス除外） |
| `x-sensitive: true` | 電話番号・口座番号など PII だが password/writeOnly が適切でない場合 |

```yaml
properties:
  password:
    type: string
    format: password          # → @JsonProperty(WRITE_ONLY) + [MASKED]
  internalToken:
    type: string
    writeOnly: true           # → @JsonProperty(WRITE_ONLY) + [MASKED]
  phoneNumber:
    type: string
    x-sensitive: true         # → @JsonProperty(WRITE_ONLY) + [MASKED]
```

### Bean Validation アノテーション（`x-validate-*`）

標準の OpenAPI キーワード（`minLength`, `maxLength`, `minimum`, `maximum`, `pattern`）は
従来どおり自動生成される。それで表現できない制約は `x-validate-*` を使う。

| YAML キー | 生成されるアノテーション | 典型的な用途 |
|---|---|---|
| `x-validate-future: true` | `@Future` | 日時フィールドが未来であること |
| `x-validate-future-or-present: true` | `@FutureOrPresent` | 現在以降の日時 |
| `x-validate-past: true` | `@Past` | 日時フィールドが過去であること |
| `x-validate-past-or-present: true` | `@PastOrPresent` | 現在以前の日時 |
| `x-validate-not-blank: true` | `@NotBlank` | 空白のみを弾く（`@NotNull` + 空白禁止） |
| `x-validate-positive: true` | `@Positive` | 正の数（0 を含まない） |
| `x-validate-positive-or-zero: true` | `@PositiveOrZero` | 0 以上の数 |
| `x-validate-negative: true` | `@Negative` | 負の数 |

```yaml
properties:
  fromDatetime:
    type: string
    format: date-time
    x-validate-future: true        # → @Future
  price:
    type: integer
    x-validate-positive: true      # → @Positive
  title:
    type: string
    x-validate-not-blank: true     # → @NotBlank
```

> **注意**: これらで表現できない業務ルール（「現在から 2 時間以上先」など相対条件）は
> `x-validate-*` では対処できない。UseCase Validator で実装する（`augment-generated-models` 参照）。

## 静的解析の除外

生成クラスは以下のツールから除外済みのため、警告対応は不要:

| ツール | 除外設定 |
|---|---|
| Checkstyle | `config/checkstyle-suppressions.xml`（`generated-sources/openapi` パターン） |
| PMD | `pom.xml` の `<excludeRoots>` |
| SpotBugs | `config/spotbugs-exclude.xml`（`generated.openapi` パッケージ） |
| JaCoCo | `pom.xml` の `<exclude>**/generated/**</exclude>` |

テンプレートファイル（`src/main/resources/openapi-templates/pojo.mustache`）は Java ソースではないため
静的解析の対象外。`pom.xml` の設定変更も静的解析に影響しない。

## トラブルシューティング

### `URISyntaxException: Illegal character in opaque part`

Windows 環境で `${project.basedir}` の `\` がそのまま URI に入るために発生する。
`pom.xml` の `maven-antrun-plugin` が Ant `<makeurl>` で正規化済みのため、スクリプト経由で実行すれば発生しない。
直接 `-Dopenapi.spec.basedir=` を渡す場合は `cygpath -m` で `C:/...` 形式に変換すること。

### `mvn: command not found`

`gen-api-models.sh` は PATH → `./mvnw` → `~/.m2/wrapper/dists/` の順で Maven を探す。
いずれにも無い場合はインストールまたは `mvnw` の配置が必要。

### YAML 構文エラー

```bash
# バリデーション（openapi-generator は生成に失敗した YAML の詳細を出さないことがある）
bash .claude/skills/_common/scripts/check-openapi-valid.sh docs/design/api/
bash .claude/skills/_common/scripts/validate-yaml-format.sh docs/design/api
```

構文エラーは docs リポジトリ側（設計書）の修正が必要。実装リポジトリ側で YAML を書き換えず、
設計変更フロー（/design-amendment）または docs PR で直してから再生成する。

<!-- 2026-07-02 修復: 末尾切断(D-1)を検出し、YAML バリデーション手順を _common/scripts の実在スクリプトと突合して復元 -->
