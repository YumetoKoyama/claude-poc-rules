# 実装レイヤ別詳細（バックエンド DTO/セキュリティ・各レイヤ完了時の中間サマリ書き出し）

implement-from-issue（backend-skills 系統）本文から 2026-07-02 に PP-5 分解で外出し。本文の該当手順から参照される。

## 2. バックエンド 詳細

   - **API モデル（DTO）の使用（必須）**: 手書き DTO は作らず、生成クラス（`com.example.logisticsmatching.generated.openapi.*`）を `@RequestBody`/`@ResponseBody` に直接使用する。フロー全体は [`../use-generated-models/SKILL.md`](../use-generated-models/SKILL.md) を参照。YAML と生成クラスの不整合を発見した場合は `claude-poc-docs` に Issue を起票して実装を中断する（YAML の直接修正禁止）。
   - **生成クラスへのセキュリティ・バリデーション要件付与（本スキルでは行わない）**: `@PreAuthorize`・テナント越境防止・UseCase Validator・PII ログマスク・Jackson 安全設定・CORS 確認等、再生成で消えるため生成クラスに直接付与できない要件の補完は `/augment-generated-models` が担う。本スキル（produce 段）では生成クラスを正しく使う実装まで行い、要件補完は後続の augment ステージに委ねる。
   - **動的クエリは Criteria API / Specification を使う（必須）**: 検索条件の動的組み立てに文字列連結を使ってはならない（R-SEC-002）。`Specification<T>` または `Criteria API` で組み立てる。ユーザー入力をソートカラムに使う場合は許可リスト（`Set.of(...)`）で検証する（R-SEC-003）。
   - **ファイルアップロード**: Issue に `multipart` / ファイルアップロード処理が含まれる場合は実装前に R-SEC-080〜082（サイズ上限・ファイル名のパストラバーサル対策・Content-Type 検証）を確認する。

## 4.1 各レイヤ完了時の中間サマリ書き出し（S7・コンテキスト溢れ対策）

DB / BE / FE の各レイヤ完了時に、次レイヤが参照すべき確定情報を**中間サマリファイル**（own リポジトリ直下 `.skills-state/implement/impl-summary-$ARGUMENTS.md`・gitignore 対象）に追記する。長い実装でコンテキストが溢れても、次レイヤはこのファイルを Read して整合を取れる。

- DB 完了時: 作成した **Entity 名・テーブル名・主キー・`version` 列の有無・一意制約**
- BE 完了時: 実装した **API パス・operationId・Request/Response DTO 名・主要フィールド名**
- FE 完了時: 作成した **画面コンポーネント名・呼び出す operationId・利用するレスポンスフィールド**
