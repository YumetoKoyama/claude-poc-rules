---
name: impact-analysis-from-change
description: 採択済みの要件または設計に変更が生じたとき、その変更が波及する下流成果物（設計ファイル・GitHub Issue・実装・テスト）を RTM（トレーサビリティマトリクス）と設計書のクロスリファレンスから機械的に特定し、影響範囲の一覧を出力する。変更対象の AC-XXX / SCR-XXX / operationId / テーブル名を入力に取り、design-amendment・reopen-issues-from-amendment の前段として使う。
context: fork
argument-hint: <変更対象 ID（AC-XXX / SCR-XXX / operationId / テーブル名）をカンマ区切り、または変更内容のメモ>
---

# 変更影響分析（RTM＋設計クロスリファレンス）

> **位置づけ**: 採択後（要件・設計が docs の `main` へマージ済み）の変更管理工程の **先頭**。実装中の ESCALATE・要件変更・設計レビュー指摘などで「採択済みの要件/設計を直す」必要が生じたとき、まず本スキルで波及範囲を機械的に洗い出し、続いて `design-amendment`（差分変更）→ `reopen-issues-from-amendment`（Issue 再オープン/追加起票）へつなぐ。変更管理の一方通行（要件→設計→Issue→実装）を、影響分析を起点に逆方向へたどれるようにするのが目的。
>
> **本スキルは分析のみ（変更しない）**: 設計書・Issue・コードは一切書き換えない。出力する影響一覧をもとに、人間が変更の採否・範囲を判断し、後続スキルへ渡す。

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は中断して人間に確認する。

変更対象: $ARGUMENTS

## 入出力

- 入力: 変更対象の ID（AC-XXX / SCR-XXX / operationId / テーブル名）または変更内容のメモ
- 入力: `docs/test/トレーサビリティマトリクス.md`（RTM。UC / AC / BR / SCR / API operationId / Issue# / TC-XXX / IT-XXX / E2E-XXX の横串正典）
- 入力: 設計書群（`docs/design/screens/`・`docs/design/api/`・`docs/design/tables/`・`docs/design/sequences/`・`docs/design/認可設計.md`・`docs/design/セキュリティ設計.md`）と要件群（`docs/requirements/`）
- 出力: `docs/design/影響分析/impact-<YYYYMMDD-HHMM>.md`（影響範囲の一覧。後続スキルの入力）
- 出力（標準出力）: 生成した影響分析ファイルのパスを 1 行

## 手順

### 1. 変更対象の正規化

1. 引数を解釈し、変更対象を **正規化した ID 集合**に落とす。
   - `AC-XXX`（受け入れ条件）・`SCR-XXX`（画面）・`UC-XXX`（ユースケース）・`BR-XXX`（業務ルール）・`ENT-XXX`（概念エンティティ）・operationId（API）・テーブル名（snake_case 物理名）を識別する。
   - 自然文メモの場合は、本文中の ID トークン（`[A-Z]+-\d{3}`・operationId 候補・テーブル名候補）を抽出し、不明確なら人間に確認する（推測で範囲を広げない）。
2. 抽出した変更対象を「変更の起点（seed）」として記録する。

### 2. RTM からの一次波及（横串トレース）

1. `docs/test/トレーサビリティマトリクス.md`（RTM）を Read する。RTM が存在しない場合は中断し、RTM 未整備を人間に報告する（影響分析は RTM を正典とするため）。
2. seed の各 ID について、RTM の行を grep ベースで突合し、同一行に並ぶ関連 ID を**一次波及**として収集する:
   - AC-XXX → 同行の UC / BR / SCR / operationId / Issue# / TC-XXX / IT-XXX / E2E-XXX
   - SCR-XXX → 同行の AC / operationId / Issue# / TC・IT・E2E
   - operationId → 同行の SCR / AC / Issue# / TC・IT・E2E
   - テーブル名 → テーブルを参照する operationId・SCR を持つ行（後述ステップ 3 で補完）
3. 収集した Issue# は「再オープン/追加起票の候補」として別枠に集約する（`reopen-issues-from-amendment` の入力になる）。

### 3. 設計書クロスリファレンスからの二次波及

RTM だけでは拾えない設計内部の連鎖を、設計書の相互参照から補完する。

1. **画面起点**: SCR-XXX が変わる場合、`docs/design/screens/SCR-XXX-*.md` が参照する operationId・遷移先 SCR（`screens/画面遷移.md` の flowchart）・メッセージ（MSG-XXX）を収集する。
2. **API 起点**: operationId が変わる場合、その operationId を参照する `docs/design/screens/*.md`・`docs/design/sequences/*.md`（SEQ-XXX）・`docs/design/認可設計.md`（operationId × ロール行）・`docs/design/api/_common.yaml`（共有スキーマ・ErrorResponse・コード値 enum）への影響を収集する。
3. **テーブル起点**: テーブル名が変わる場合、`docs/design/tables/<テーブル名>.md`（部分 ER）・`docs/design/DB定義.md`（全体 ER）・当該テーブルを読み書きする operationId・SEQ・並行制御（version 列 / 一意制約）への影響を収集する。
4. **シーケンス/認可/セキュリティ起点**: SEQ-XXX・認可行・セキュリティ値（JWT・BCrypt 等）に変更が及ぶ場合は、関係する operationId・SCR・テーブルへ逆引きする。
5. 各波及には **波及理由（どの参照を辿ったか）** を 1 行で添える（追跡可能にするため）。

### 4. 実装・テスト成果物への波及推定

1. 一次・二次波及で得た operationId・SCR・テーブルから、影響を受ける **実装リポジトリと層** を推定して列挙する:
   - テーブル → backend の Entity / Repository / migration（または `ddl-auto` 運用時は Entity）/ `docs/design/tables/*.md`
   - operationId → backend の Controller / UseCase（application）/ DTO / `@PreAuthorize`、frontend の API クライアント・型
   - SCR → frontend の画面コンポーネント・ルーティング・状態
2. RTM の TC-XXX / IT-XXX / E2E-XXX 列から、再設計・再実行が必要なテストを列挙する（単体は製造、結合は結合テスト工程、E2E は別工程の責務である旨を併記）。

### 5. 影響分析レポートの出力

`docs/design/影響分析/impact-<YYYYMMDD-HHMM>.md` を作成し、次の構成で出力する。

```markdown
# 変更影響分析 <YYYYMMDD-HHMM>

## 1. 変更の起点（seed）
| 変更対象 ID | 種別 | 変更概要（人間記入欄） |
|---|---|---|

## 2. 一次波及（RTM 横串）
| 起点 | 波及先 ID | 種別 | 出典（RTM 行） |
|---|---|---|---|

## 3. 二次波及（設計クロスリファレンス）
| 起点 | 波及先ファイル/ID | 波及理由（辿った参照） |
|---|---|---|

## 4. 影響を受ける実装・テスト
| 区分 | 対象（リポ/層/ファイル候補） | 出典 |
|---|---|---|

## 5. 再オープン/追加起票の候補 Issue
| Issue# | 関連 ID | 理由 | 推奨アクション（再オープン/追加/不要） |
|---|---|---|---|

## 6. 凡例
（本ファイルで使用した略号一覧）
```

最後に、生成したファイルの絶対/相対パスを標準出力へ 1 行で出す。

## 完了条件

- seed が正規化され、RTM 一次波及と設計二次波及の両方が収集されている
- 影響を受ける実装・テスト成果物が列挙されている
- 再オープン/追加起票の候補 Issue がセクション 5 に集約されている
- `docs/design/影響分析/impact-<...>.md` が出力され、パスが標準出力に出ている

## 凡例

| 略号 | 正式名称 | 補足 |
| --- | --- | --- |
| RTM | トレーサビリティマトリクス | `docs/test/トレーサビリティマトリクス.md`。横串カバレッジの正典 |
| AC-XXX | 受け入れ条件 ID | 3 桁ゼロ埋め |
| SCR-XXX | 画面 ID | 3 桁ゼロ埋め |
| UC-XXX | ユースケース ID | 3 桁ゼロ埋め |
| BR-XXX | 業務ルール ID | 3 桁ゼロ埋め |
| ENT-XXX | 概念エンティティ ID | 3 桁ゼロ埋め |
| SEQ-XXX | シーケンス ID | `docs/design/sequences/*.md` |
| operationId | API 操作 ID | OpenAPI の operationId |
| seed | 変更の起点 | 影響分析の出発点となる ID 集合 |

## 注意事項

- 本スキルは分析のみ。設計書・Issue・コードを書き換えない（変更は `design-amendment` の責務）。
- RTM を正典とする。RTM が無い・古い場合は中断して人間に整備を依頼する（推測で波及範囲を作らない）。
- 波及には必ず出典（RTM 行・辿った参照）を添え、追跡可能にする。
- 強調表記は鉤括弧 `「...」` を使う。
