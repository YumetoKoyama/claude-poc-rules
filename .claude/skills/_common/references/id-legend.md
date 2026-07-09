# ID 凡例（共通・単一正典）

【P-14 / C-2 対応（2026-07-02 改善）】従来は各画面 md 等に同じ「ID 凡例」表が重複していた。本ファイルを唯一の凡例正典とし、**各成果物は凡例表を再掲せず本ファイルへのリンクを 1 行置く**（例: `ID 凡例: [id-legend.md](../../.claude/skills/_common/references/id-legend.md) 参照`。docs リポジトリに成果物を置く場合は、設計フェーズ初回にこのファイルを `docs/凡例.md` へコピーし、以後はそちらを参照する）。

新しい ID 体系・略号を導入する場合は、導入した produce スキルの実行内で本凡例への追記案を提示し、人手で反映する（勝手に増やさない）。

| プレフィックス | 意味 | 定義元（正典） |
|---|---|---|
| SCR- | 画面 | 要件 `画面一覧.md` / 設計 `screens/` |
| UC- | ユースケース | 要件 `ユースケース図.md` |
| ACT- | 業務アクティビティ | 要件 `activities/` |
| AC- | 受け入れ条件（機能スコープ採番。機能外からの参照は `機能名/AC-XXX` で修飾・R-01） | 要件 `functional/*.md` |
| BR- | 業務ルール | 要件 `業務ルール.md` |
| ENT- | 概念エンティティ | 要件 `データモデル.md` |
| ST- | 状態 | 要件 `データモデル.md`（状態遷移） |
| EXT- | 外部インターフェース | 要件 `外部インターフェース一覧.md` |
| MIG- | 移行 | 要件 `移行要件.md` |
| MSG- | メッセージ | 要件 `メッセージ一覧.md` |
| Q- | オープン課題（Q-NF/Q-DM/Q-EI/Q-MIG/Q-BR 等の区分つき） | 要件 `オープン課題.md` |
| SEQ- | シーケンス | 設計 `sequences/` |
| TC- | 単体テスト | 製造 `単体テストマトリクス`（/test-design-from-issue） |
| IT- | 結合テスト | 結合テスト工程（/integration-test-from-design） |
| E2E- | E2E テスト | E2E 工程（凍結中は Decision Log 参照） |
| D- | 意思決定（Decision Log） | `docs/process/decision-log.md`（運用: `07-decision-log.md`） |
| CP- | 正典差分提案 | `canon-proposals/`（/propose-canon-patch） |
| RC- / S- / M- / L- / P- | プロセス改善の内部管理番号（ルール・課題の由来追跡用） | 課題台帳・CLAUDE.md 内の参照 |

採番規約: 英字プレフィックス + 3 桁ゼロ埋め連番（shared-canon §1）。要件・設計・テストで同じ ID を引用して縦串トレースを成立させる。

例外（D- のみ）: 意思決定 ID は運用実態に合わせて **2 桁連番**（`D-01`〜）とする。hooks・`_common/scripts`・skill 本文で既に 2 桁形式が定着しているため、他プレフィックスの 3 桁ゼロ埋めとは別扱いとする。新規追加時も `D-01`〜`D-99` の範囲で採番し、`docs/process/decision-log.md` に行を追加する。
