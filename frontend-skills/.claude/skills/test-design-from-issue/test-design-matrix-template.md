# テスト設計マトリクステンプレート（RTM）

単体テストマトリクスの様式は [unit-test-from-design/unit-test-matrix-template.md](../unit-test-from-design/unit-test-matrix-template.md) を参照する。本ファイルは **トレーサビリティマトリクス（RTM）** の様式を示す。

> **フロントエンドに IT 層はない**: フロントエンドは DB に直接アクセスしないため結合テスト（IT-XXX）は存在しない。RTM に IT-XXX 列は設けない。

## 凡例

| 略号 | 正式名称 | 補足 |
| --- | --- | --- |
| TC-XXX | 単体テストケース ID | 3 桁ゼロ埋め |
| E2E-XXX | E2E テストケース ID | 3 桁ゼロ埋め（現環境では別工程・空欄可） |
| AC-XXX | 受け入れ条件 | 要件定義 `functional/*.md` で定義 |
| IMPL-XX | 実装内容項目 | AC が無い基盤 Issue で設計書「実装内容」を観点化した一時 ID |
| BR-XXX | 業務ルール | 要件定義 `業務ルール.md` で定義 |
| SCR-XXX | 画面 ID | 3 桁ゼロ埋め |

---

## トレーサビリティマトリクス / RTM（docs/test/トレーサビリティマトリクス.md）

要件→設計→Issue→テストを 1 表に集約し、横串でカバレッジ漏れを検出する正典。Issue 起票・実装ループで更新する。

| UC | AC / 実装内容項目 | BR | SCR | API operationId | Issue# | TC-XXX | E2E-XXX |
| --- | --- | --- | --- | --- | --- | --- | --- |
| UC-001 | AC-001 | BR-002 | SCR-001 | createXxx | #12 | TC-001, TC-002 | — |
| —（基盤） | IMPL-01 認証フック | — | — | — | #4 | TC-001〜TC-010 | — |

- AC が無い基盤 Issue は「AC / 実装内容項目」列に実装内容項目（IMPL-XX ＋ 項目名）を入れ、空欄にしない。
- E2E は現環境では別工程のため `—` を入れてよい。
- **IT-XXX 列はフロントエンドには存在しない**（バックエンドの RTM とは列数が異なる）。
