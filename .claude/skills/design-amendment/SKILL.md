---
name: design-amendment
description: 採択済みの設計書に対する差分変更を管理する。変更理由（ESCALATE / 要件変更 / レビュー指摘）を記録し、変更前後の diff を docs/design/変更履歴.md に追記する。design-from-requirements の再実行とは異なり、impact-analysis-from-change で特定した変更箇所のみを修正し、影響範囲外のファイルには触れない。変更後は reopen-issues-from-amendment へつなぐ。
context: fork
argument-hint: <影響分析ファイルのパス（docs/design/影響分析/impact-*.md）または変更対象 ID と変更理由>
---

# 設計変更（差分変更＋変更履歴）

> **位置づけ**: 変更管理工程の中段。`impact-analysis-from-change` が特定した波及範囲をもとに、採択済み設計の **変更箇所のみ**を最小差分で修正する。`design-from-requirements`（設計の全面生成）とは別物であり、影響範囲外のファイルは触らない（加算型・最小差分の原則）。変更後は `reopen-issues-from-amendment` で Issue を再オープン/追加起票する。
>
> **採択ゲートとの関係**: 本スキルが書き換えるのは docs リポジトリの設計書（作業ブランチ）。変更を採択済みにするには、人間が PR をレビューして docs の `main` へマージする必要がある（マージ＝採択）。Claude・skill は自ら PR をマージしない。

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合は中断して人間に確認する。

入力: $ARGUMENTS

## 入出力

- 入力: `impact-analysis-from-change` が出力した影響分析ファイル（`docs/design/影響分析/impact-*.md`）、または変更対象 ID と変更理由
- 入力: 変更対象の設計書（`docs/design/` 配下）と、必要に応じて採択済み要件（`docs/requirements/`）
- 出力: 変更された設計書ファイル（最小差分）
- 出力: `docs/design/変更履歴.md`（変更理由・変更前後 diff を追記）
- 出力（標準出力）: 変更したファイル一覧と変更履歴のパス

## 前提条件

- 変更対象の設計書が既に採択済み（docs の `main` にマージ済み）であること。未採択の設計をいじる場合は `design-amendment` ではなく通常の `design-loop` を使う。
- 影響分析（`impact-analysis-from-change`）が実施済みで、変更すべきファイルと波及範囲が特定されていること。未実施なら先に `impact-analysis-from-change` を実行する（影響範囲外を巻き込まないため）。

## 手順

### 1. 変更スコープの確定

1. 影響分析ファイルが渡された場合は Read し、「変更の起点（seed）」と「影響を受ける設計ファイル」を取り出す。直接 ID と理由が渡された場合は、まず `impact-analysis-from-change` の実行を促す（影響範囲が未確定なまま編集しない）。
2. **変更してよいファイル集合**を確定し、それ以外には触れないことを宣言する（影響範囲外の設計書・要件・コードは対象外）。
3. 変更理由を区分する: `ESCALATE`（実装/レビューで設計の不備が判明）/ `要件変更`（採択済み要件の改訂に追随）/ `レビュー指摘`（review-design 等の継続指摘）。

### 2. 変更前スナップショットの取得

1. 変更対象ファイルそれぞれについて、変更前の該当箇所（行範囲・該当表・該当 YAML ブロック等）を退避し、diff の「変更前」側として保持する。
2. `git diff` が使える場合は変更後にコミット前 diff を取得できるよう、作業ブランチであることを確認する。

### 3. 最小差分での修正

1. 確定したファイル集合のみを、**変更が必要な箇所のみ**書き換える。無関係な整形・再生成・章番号の付け替えは行わない（加算型・最小差分）。
2. 界面契約に関わる変更（ErrorResponse・コード値 enum・operationId・認可行）は、正典である `docs/design/api/_common.yaml`・`docs/design/認可設計.md`・要件 `コード値定義.md` と一字一句一致させる（縦串の不整合を新たに作らない）。
3. 並行制御・テーブル変更を伴う場合は、`tables/*.md` の version 列・一意制約・DB定義の ER と整合を保つ。
4. 変更により新たな未確定事項が生じた場合は本文に断定で書かず、`docs/requirements/オープン課題.md` または影響分析へ切り出す。

### 4. 変更履歴の追記（docs/design/変更履歴.md）

`docs/design/変更履歴.md` が無ければ凡例付きで新規作成し、あれば追記する。各変更を 1 エントリとして次の様式で記録する。

```markdown
## 変更 <YYYYMMDD-HHMM> / 起点: <seed ID 群>

- 変更理由区分: ESCALATE / 要件変更 / レビュー指摘
- 変更理由（詳細）: <なぜ変えたか。関連 Issue#・review JSON・要件改訂を参照>
- 影響分析: docs/design/影響分析/impact-<...>.md
- 変更ファイル一覧:
  - docs/design/<file>: <一言サマリ>

### 変更前後 diff
（変更ファイルごとに、変更前→変更後の該当箇所を fenced diff で記録）
```

### 5. 変更の検証

1. 変更したファイルに対して `bash .claude/skills/_common/scripts/check-truncation.sh <変更ファイル>` を実行し、切断（不完全な文・テーブル行・YAML）を検出する。
2. 界面契約・縦串の整合が崩れていないか、変更箇所の参照先（operationId・SCR・テーブル・コード値）の実在を確認する。
3. 影響範囲外のファイルに差分が出ていないこと（最小差分）を `git status` で確認する。

### 6. まとめ出力

変更したファイル一覧・変更理由区分・変更履歴のパスを標準出力に出す。続けて `reopen-issues-from-amendment` を実行して、影響を受ける Issue の再オープン/追加起票へ進むよう案内する。

## 完了条件

- 影響分析で確定したファイルのみが最小差分で変更されている（影響範囲外に差分が無い）
- `docs/design/変更履歴.md` に変更理由区分・詳細・変更前後 diff が追記されている
- 変更ファイルが check-truncation を通過し、界面契約・縦串の整合が保たれている
- 次工程（reopen-issues-from-amendment）への案内が出ている

## 凡例

| 略号 | 正式名称 | 補足 |
| --- | --- | --- |
| 変更理由区分 | ESCALATE / 要件変更 / レビュー指摘 | 変更履歴の必須項目 |
| seed | 変更の起点 | 影響分析が特定した変更対象 ID 集合 |
| RTM | トレーサビリティマトリクス | `docs/test/トレーサビリティマトリクス.md` |
| operationId | API 操作 ID | OpenAPI の operationId |

## 注意事項

- 影響範囲外のファイルを触らない（最小差分・加算型）。全面再生成が必要なら `design-loop` を使う。
- 界面契約（ErrorResponse・コード値・operationId・認可）は正典と一字一句一致させ、新たな縦串不整合を作らない。
- 自ら PR をマージしない。採択は人間の PR マージで行う。
- 強調表記は鉤括弧 `「...」` を使う。
