# OpenAPI Generator 実行エントリの同期（Java バックエンド限定）

<!-- 2026-07-02 再生成: 末尾切断(D-1)を実装実態（pom.xml の openapi-gen-* エントリ・scripts/gen-api-models.sh・SKILL.md 手順2.5/6）と突合して復元 -->

`pom.xml` の `openapi-generator-maven-plugin` は **YAML ファイルごとに `<execution>` エントリを手動管理**する仕組みであり、`docs/design/api/` を自動検出しない。
docs リポジトリで YAML が追加・削除・リネームされると `pom.xml` との乖離がビルドエラー（`Unable to read location`）を起こすため、ブランチ作成の前に必ず同期を確認する。

## 確認手順

1. docs リポジトリの `docs/design/api/` に存在する YAML ファイルを列挙する（`_common.yaml` は除外）
   - docs の場所は SKILL.md 冒頭「パス解決」に依存する（親アンブレラ: `claude-poc-docs/docs/design/api/`・CI: checkout パス）
2. `pom.xml` 内の `<id>openapi-gen-*</id>` エントリと照合する:
   - **YAML は存在するが pom.xml にエントリがない** → `openapi-generator-maven-plugin` の `<executions>` 末尾に追加する:
     ```xml
     <execution>
       <id>openapi-gen-{stem}</id>
       <goals><goal>generate</goal></goals>
       <configuration><inputSpec>${openapi.spec.uri}/{stem}.yaml</inputSpec></configuration>
     </execution>
     ```
     `{stem}` はファイル名から `.yaml` を除いた部分（例: `applications.yaml` → `applications`）
   - **pom.xml にエントリはあるが対応 YAML が存在しない** → そのエントリを `pom.xml` から削除する
   - **完全一致** → 変更不要
3. `pom.xml` を変更した場合は、手順6（コミット）に必ず含める（コード本体と同一 feature ブランチ・同一 PR でよい。docs リポジトリ側は変更しない）
4. **同期後の検証**: `scripts/gen-api-models.sh`（無ければ `mvn generate-sources`）を実行し、全 YAML の生成が成功して `Unable to read location` が出ないことを確認してから実装に進む。生成された `generated.openapi.*` モデルと手書きコードの整合は SKILL.md 本文の手順（use-generated-models）に従う
