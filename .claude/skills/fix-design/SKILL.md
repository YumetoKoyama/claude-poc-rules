---
name: fix-design
description: review-design が生成した review JSON の BLOCK・SUGGEST・NIT を docs/design/ に反映する。design-loop オーケストレータから呼ばれる。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
---

# 設計書の修正
> **STATE_DIR の解決（D-03・最初に必ず 1 回）**: `STATE_DIR="$(bash .claude/skills/_common/scripts/state-dir.sh design)"` を実行し、以降の `<STATE_DIR>` はこの絶対パスを指す。`.skills-state/...` の相対パス直書きは禁止（書き手による state 置き場の分裂防止）。


> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4 における **fix** 段を担当します。

**`context: fork` 必須**: 入力（review JSON）と出力（docs/design/ の修正）がファイル経由のため。

## 役割

直近の review JSON を入力に、**BLOCK・SUGGEST・NIT** をすべて修正する。スキップした指摘は該当箇所にレビューマーカーを残す。

## 入出力

- 入力: `<STATE_DIR>/state.json`（`last_review_path` を取得）
- 入力: 該当する `<STATE_DIR>/round-<N>-review.json`
- 入力: `docs/design/` 配下、整合確認のため `docs/requirements/` も参照可
- 出力: `docs/design/` 配下の修正

## 編集範囲ガード（D-01・必須）

- 本 skill が Edit / Write してよいのは **`docs/design/` 配下のみ**。`docs/requirements/` 配下は**採択済み正典**であり編集禁止（フェーズ分離・採択ゲートの回避にあたる）。
- 要件側の記載不備・確定値未反映に起因する指摘は、要件を直接修正する代わりに:
  1. `<STATE_DIR>/requirements-feedback.md` に「Q-ID / 対象ファイル / 提案内容 / 根拠 finding」を追記する。
  2. 当該 finding は『要件フィードバック起票』として対応済み扱いにする（verify-fix はこのマーカーを addressed と認める）。
  3. 要件への実反映は人手採択で行う（`docs/process/11-adoption-checklist.md`）。

## 手順

1. **state を Read** → `last_review_path` 取得
2. **review JSON を Read** → BLOCK + SUGGEST + NIT をリスト化（すべて修正対象）
3. **修正計画**:
   3.1. **読み込みスコープ**: 設計書全体を Read するのではなく、review JSON の各 finding の `path`（指摘対象ファイル）と `related_files`（関連ファイル）をまず読む。これが修正に必要なファイルの一次スコープとなる。波及先チェックリスト（後述）で追加の確認が必要と判断した場合にのみ、スコープ外のファイルを読む。
   3.2. OpenAPI YAML 修正は `_common.yaml` 改訂の波及を見て一括対応
   3.3. DB 修正は `DB定義.md` の全体 ER 図と `tables/*.md` の部分 ER 図を**両方更新**
   3.4. 画面修正は `画面一覧.md` の画面遷移図とも整合させる
4. **修正を適用**（Edit / Write）
4.5. **修正後の決定論スクリプト検証（ADD-2、必須）**: 修正適用後、以下のスクリプトを**すべて実行**し、NG（exit 1）があればその場で追加修正する。追加修正後に再度全スクリプトを実行し、全て OK になるまで繰り返す（最大 2 回。2 回で解消しない場合は stdout に未解消の NG を出力して先に進む）。

   ```bash
   # 各スクリプトは独立（共有状態・依存関係なし）なので並列実行で時間短縮する
   bash .claude/skills/_common/scripts/check-openapi-valid.sh docs/design/api/                          &
   bash .claude/skills/_common/scripts/check-contract.sh docs/design/                                   &
   bash .claude/skills/_common/scripts/check-db-design-consistency.sh docs/design/                      &
   bash .claude/skills/_common/scripts/check-vertical-trace.sh docs/design/                             &
   bash .claude/skills/_common/scripts/check-truncation.sh docs/requirements/ docs/design/              &
   bash .claude/skills/_common/scripts/validate-yaml-format.sh docs/design/api                          &
   bash .claude/skills/_common/scripts/check-confirmed-values.sh docs/requirements/ docs/design/ docs/requirements/ &
   wait  # 全スクリプトの完了を待つ
   ```

   **目的**: fix が BLOCK を解消する過程で生じた副作用（operationId 重複、enum 値の不整合、テーブル定義の不足、縦串の断絶、ファイル破損等）を、次の review ラウンドに渡す前にこの fix 内で検出・修正する。スクリプトは決定論（同じ入力 → 同じ出力）なので、修正すれば確実に NG が消える。

   > 注: スクリプトのカバレッジ外の整合（data-sufficiency のフィールドレベル照合等）は引き続き LLM レビュー（次ラウンド）が担当する。ここでは**スクリプトで検出可能な副作用を fix 段階で潰す**ことに集中する。
5. **レビューマーカーを挿入**: スキップした指摘（SUGGEST・NIT 問わず）の該当箇所にマーカーコメントを挿入（「レビューマーカー」節参照）
6. **修正サマリを stdout に**

## ルール

- BLOCK は必修。対応不能なら ESCALATE。
- SUGGEST は対応。要件側の追加判断が必要なものは ESCALATE ではなく「skipped SUGGEST: <理由>」で済ませる。
- **NIT も極力対応する**。表記揺れ・命名規約・体裁・Mermaid 図の軽微な修正など、要件の意思決定を伴わないものは修正する。対応コストが大きい場合のみスキップ可（stdout に「skipped NIT: <理由>」）。
- **スキップした SUGGEST・NIT は該当箇所にレビューマーカーを残す**（後述「レビューマーカー」節参照）。
- **設計フェーズ中に要件の意思決定をしない**（CLAUDE.md ルール）。要件追加が必要と思ったら ESCALATE。

## 設計書修正の波及先チェックリスト（修正前に確認・影響があれば連鎖更新）

修正で以下の種類の変更を行う場合、右列の文書を**確認し、影響があれば同時に更新する**。影響がなければ更新不要（不要な更新は別の副作用を生む）。波及先を確認せず放置すると、次ラウンドの review で新たな BLOCK として検出される（fix の副作用）。

| 変更の種類 | 影響を確認すべき文書 |
|-----------|-------------------|
| **operationId の追加・変更・削除** | `api/*.yaml`（定義元）、`認可設計.md`（operationId × ロール × テナント条件の行）、`screens/*.md`（参照している画面の API 欄）、`sequences/*.md`（呼び出し箇所） |
| **API スキーマフィールドの追加・変更** | `api/_common.yaml`（共通スキーマなら $ref 元）、`tables/*.md`（対応カラムの型・桁・NULL・enum）、`screens/*.md`（データ需給表のフィールド参照）、`DB定義.md`（全体 ER 図のカラム） |
| **テーブルカラムの追加・変更** | `tables/*.md`（部分 ER 図）、`DB定義.md`（全体 ER 図）、`api/*.yaml`（対応スキーマの properties）、`sequences/*.md`（INSERT/UPDATE の列リスト） |
| **enum 値の追加・変更** | `api/_common.yaml`（enum 定義の正典）、`コード値定義.md`（要件。設計から逆流しないなら ESCALATE）、`screens/*.md`（凡例の CODE=表示名）、`tables/*.md`（カラム型の enum 列挙） |
| **画面の表示項目の追加** | `screens/*.md`（データ需給表に供給元 operationId.フィールドを明記）、供給元がなければ `api/*.yaml` にフィールド追加 → 上記「API スキーマフィールド」の連鎖 |
| **シーケンスの追加・変更** | `sequences/*.md`（SEQ-XXX 採番・Mermaid sequenceDiagram）、参照する operationId が `api/*.yaml` に実在すること、INSERT/UPDATE の列が `tables/*.md` に実在すること |
| **`_common.yaml` の変更** | 他の `api/*.yaml` の `$ref` 参照先が壊れないこと、`共通部品設計.md` のフィールド名記述との一致、`フロントエンド共通設計.md` の型定義との一致 |
| **認可設計の変更** | `セキュリティ設計.md`（認可方式との整合）、`api/*.yaml`（description の必要ロール記述）、`権限マトリクス.md`（要件。設計から逆流しないなら ESCALATE） |

### 使い方

1. review JSON の各 finding の `suggested_fix` を読み、**変更の種類**を特定する
2. 上表で波及先を確認し、**影響があるもの**を洗い出す
3. finding の修正と、影響のある波及先の更新を**同じ修正バッチ**で行う（影響のない文書は触らない）
4. Step 4.5 のスクリプト検証で漏れがないか機械確認する

## レビューマーカー

スキップした SUGGEST・NIT は、該当箇所にマーカーコメントを挿入する。

### 形式

Markdown ファイル:

```
<!-- REVIEW-SUGGEST: [RD-042] SEQ-001 の alt フローが未記載 -->
<!-- REVIEW-NIT: [RD-058] erDiagram の属性名に表記揺れ -->
```

YAML ファイル:

```yaml
# REVIEW-SUGGEST: [RD-042] 404 レスポンスの description が不足
# REVIEW-NIT: [RD-058] operationId の命名に揺れ
```

### ルール

- `REVIEW-SUGGEST:` / `REVIEW-NIT:` を prefix とする（既存の `TODO` / `FIXME` と区別するための専用 prefix）。
- review JSON の finding ID があれば `[RD-042]` 形式で付与する。
- 該当箇所の **直前行** に挿入。特定できない場合はファイル末尾にまとめる。
- マーカーは修正ではないため、既存の文面・スキーマを書き換えない。
- Mermaid ブロック内にはコメントを入れない（構文エラー防止）。Mermaid ブロックの直前に挿入する。
- OpenAPI YAML のコメントは仕様上有効だが、`$ref` 解決に影響しない位置に置く。

## 注意事項

- Mermaid 構文は壊さない（`erDiagram` / `flowchart` の構文エラーで設計書が読めなくなる）
- OpenAPI 3.1 構文を壊さない（yaml パース + spec 検証が可能な状態を保つ）
