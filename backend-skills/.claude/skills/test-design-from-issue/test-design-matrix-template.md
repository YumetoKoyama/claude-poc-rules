# テスト設計マトリクステンプレート（結合テスト・RTM）

単体テストマトリクスの様式は [unit-test-from-design/unit-test-matrix-template.md](../unit-test-from-design/unit-test-matrix-template.md) を参照する。本ファイルは **結合テストマトリクス** と **トレーサビリティマトリクス（RTM）** の様式を示す。

## 凡例

| 略号 | 正式名称 | 補足 |
| --- | --- | --- |
| TC-XXX | 単体テストケース ID | 3 桁ゼロ埋め |
| IT-XXX | 結合テストケース ID | 3 桁ゼロ埋め |
| E2E-XXX | E2E テストケース ID | 3 桁ゼロ埋め（現環境では別工程・空欄可） |
| AC-XXX | 受け入れ条件 | 要件定義 `functional/*.md` で定義 |
| IMPL-XX | 実装内容項目 | AC が無い基盤 Issue で設計書「実装内容」を観点化した一時 ID |
| BR-XXX | 業務ルール | 要件定義 `業務ルール.md` で定義 |
| SCR-XXX | 画面 ID | 3 桁ゼロ埋め |

---

## 結合テストマトリクス（docs/test/結合テストマトリクス.md）

Controller→Service→Repository→DB の実結合・サービス間結合（通知発火 × トランザクション境界・排他制御）を IT-XXX で採番する。単体（Service モック）と E2E（ブラウザ）の中間層を埋める。

| IT-ID | 対応 AC / 実装内容項目 | 結合範囲（操作） | API operationId | SCR | 区分 | シナリオ | 期待結果 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IT-001 | AC-001 | Controller→Service→Repository→DB | createXxx | SCR-001 | 正常系 | 有効入力で登録 | 201・DB に永続化 |
| IT-002 | AC-002 | Controller→Service（認可） | getXxx | SCR-001 | 権限境界 | 他テナントの資源参照 | 403・参照不可 |

### 当該 Issue で結合テストを後続送りにする場合

IT 行を採番できない場合（共通部品のみで結合点が無い等）も本ファイルを作成し、下表のように **対象外＋理由** を明記する（空ファイル・不在は不可）。

| IT-ID | 区分 | 対象 | 理由 |
| --- | --- | --- | --- |
| — | 対象外 | 共通部品（JWT フィルタ・GlobalExceptionHandler 等） | 結合点は後続 API Issue で @SpringBootTest + Testcontainers により検証する |

---

## トレーサビリティマトリクス / RTM（docs/test/トレーサビリティマトリクス.md）

要件→設計→Issue→テストを 1 表に集約し、横串でカバレッジ漏れを検出する正典。Issue 起票・実装ループで更新する。

| UC | AC / 実装内容項目 | BR | SCR | API operationId | Issue# | TC-XXX | IT-XXX | E2E-XXX |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| UC-001 | AC-001 | BR-002 | SCR-001 | createXxx | #12 | TC-001, TC-002 | IT-001 | — |
| —（基盤） | IMPL-01 認証フィルタ | — | — | — | #4 | TC-001〜TC-010 | 対象外 | — |

- AC が無い基盤 Issue は「AC / 実装内容項目」列に実装内容項目（IMPL-XX ＋ 項目名）を入れ、空欄にしない。
- E2E は現環境では別工程のため `—` を入れてよい。
- **TC-XXX は複数 Issue 横断で一意**（RC4 / T-03）: 既存マトリクスの最大 TC 番号の続番から採番する（Issue ごとに TC-001 へ戻さない）。重複は `check-test-matrix.sh` のハードゲートで弾かれる。
- **状態遷移・並行制御・契約系の観点**: 状態遷移エンドポイント（楽観/悲観ロック・409）の正常/異常、テナント越境（UPDATE/DELETE/COUNT/集計を含む）、契約（OpenAPI⇔FE型⇔BE DTO）の不一致検出は、TC（単体）と IT（結合工程）の双方で適切な層に割り当てて網羅する。
