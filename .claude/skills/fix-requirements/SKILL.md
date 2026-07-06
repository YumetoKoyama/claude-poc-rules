---
name: fix-requirements
description: review-requirements が生成した review JSON の BLOCK・SUGGEST・NIT を docs/requirements/ に反映する。requirements-loop オーケストレータから呼ばれる。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
---

# 要件定義の修正
> **STATE_DIR の解決（D-03・最初に必ず 1 回）**: `STATE_DIR="$(bash .claude/skills/_common/scripts/state-dir.sh requirements)"` を実行し、以降の `<STATE_DIR>` はこの絶対パスを指す。`.skills-state/...` の相対パス直書きは禁止（書き手による state 置き場の分裂防止）。


> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4 における **fix** 段を担当します。

**`context: fork` 必須**: 入力（review JSON）と出力（docs/requirements/ の修正）が完全にファイル経由なので、main 文脈を持ち込まない方がレビュー指摘との一対一対応が崩れない。

## 役割

直近の review JSON を入力に、**BLOCK・SUGGEST・NIT** をすべて修正する。スキップした指摘は該当箇所にレビューマーカーを残す。

## 入出力

- 入力: `<STATE_DIR>/state.json`（`last_review_path` を取得）
- 入力: 該当する `<STATE_DIR>/round-<N>-review.json`
- 入力: `docs/requirements/` 配下の Markdown
- 出力: `docs/requirements/` 配下の修正（Edit / Write で適用）

## 手順

1. **state を Read**: `last_review_path` から最新 review JSON のパスを取得。
2. **review JSON を Read**: `findings` を **BLOCK → SUGGEST → NIT の順** で保持。すべて修正対象。
3. **修正計画を立てる**:
   - 同一ファイル × 同一カテゴリの指摘はまとめて 1 回の編集で対応
   - 修正後に他の BLOCK と矛盾しないかを確認（例: AC-003 を追加する BLOCK 修正が、別の SUGGEST 「冗長な AC を整理」と衝突しないか）
4. **修正を適用**: Edit / Write で対象ファイルを更新。差分は最小限に。
4.5. **修正後の簡易整合チェック（ADD-2・必須）**: 修正を適用したファイル間で、次の 3 点を機械的に確認し、新しい不整合があれば**同じ fix 内で**修正する（次の review iteration を待たない）:
   - **追加 ID の定義確認**: 今回追加・変更した ID（AC-XXX / UC-XXX / BR-XXX / SCR-XXX / ENT-XXX / EXT-XXX / MIG-XXX 等）が、参照先と出典の双方で定義済みか。新規略号は当該ファイル冒頭の凡例表に追記済みか。
   - **ステータス・用語集整合**: 追加・変更したステータスが `用語集.md` のステータス定義（および状態遷移図）に含まれるか。第 1 版で「使用しない」と定義したステータスへ参照を増やしていないか。
   - **画面遷移整合**: 追加・変更した画面遷移が `画面一覧.md` の遷移図、および `functional/[機能名].md` の「完了後の動作」と一致するか（同一操作の遷移先が 1 つに統一されているか）。
   `requirements-guardrails/references/consistency-checklist.md` の手順に従って確認する。発見した不整合を本 fix 内で潰せない場合（要件意思決定が必要等）は ESCALATE を出す。
5. **レビューマーカーを挿入**: スキップした指摘（SUGGEST・NIT 問わず）について、該当箇所にマーカーコメントを挿入する（「レビューマーカー」節参照）。
6. **修正サマリを stdout に出力**: 「BLOCK X 件 / SUGGEST Y 件を反映、マーカー挿入 Z 件、整合再チェック OK」のように 1〜2 行で報告。

## ルール

- **BLOCK は必修**。1 件も残さず対応する。対応不能な BLOCK があれば（要件追記の判断にユーザー意思決定が必要等）、stdout で「ESCALATE: <理由>」と明記して終了。orchestrator が止める。
- **SUGGEST は対応する**。ただし対応が大きく要件の意思決定が必要なものはスキップしてよい（その場合 stdout に「skipped SUGGEST: <理由>」を出す）。
- **NIT も極力対応する**。表記揺れ・体裁・軽微な改善など、要件の意思決定を伴わないものは修正する。対応コストが大きい場合のみスキップしてよい（stdout に「skipped NIT: <理由>」を出す）。
- **スキップした SUGGEST・NIT は該当箇所にレビューマーカーを残す**（後述「レビューマーカー」節参照）。
- **review JSON にないファイルは触らない**。
- 修正中に新しい要件意思決定（業務ルール追加・画面新設等）が必要になったら、勝手に判断せず ESCALATE を出して人手介入を要求する。
- 修正後に review skill 用の状態は触らない（state 更新は orchestrator が advance-state.sh で行う）。

## カテゴリ別の修正方針

review JSON の `category` ごとに、典型的な修正方法を示す（BLOCK / SUGGEST 共通）。

- `traceability` / `legend`: 参照されているのに未定義の ID（AC-XXX / UC-XXX / SCR-XXX 等）を、出典資料側に定義として追加するか、参照側を実在 ID に修正する。略号が初出なら当該ファイル冒頭の凡例表に追記する。
- `status-drift`: 用語集のステータス定義を正として、業務ルール・画面仕様・フロー図の表記をそろえる。「第 1 版では使用しない」と定義したステータスへの参照は削除する。
- `impl-leak`: フレームワーク名・ライブラリ名・DB カラム名・API パスを要件本文から除去し、業務観点の表現に置き換える（設計の意思決定は持ち込まない）。
- `open_question_closure` / `security_baseline` / `operational`: 本文に断定値を書かず、`オープン課題.md` の `Q-NF*` 等へ切り出し、本文からは参照のみにする。クローズ運用ルール章が無ければ追加する。
- `exception`: 同時操作競合・取消可否・差戻し・論理削除中表示などの例外系を、該当 `functional/*.md` または `業務ルール.md` に「条件 → 結果」形式で追記する。
- `data_model` / `external_interface` / `migration`: 不足エンティティ・状態遷移・EXT/MIG エントリを追加する。「なし」と判断するなら根拠つきでその旨を明記する。
- `ambiguity` / `testability` / `nonfunc-value`: 「適切に」等の曖昧語を具体条件・要求値（数値・期間・対象）に置き換える。
- `naming` / `term_variation` / `redundancy`: 用語集を正として表記統一し、重複定義は 1 箇所に集約して他は参照にする。

同一ファイル × 同一カテゴリの指摘はまとめて 1 回の編集で対応する。

## レビューマーカー

スキップした SUGGEST・NIT は、該当箇所に以下の形式でマーカーコメントを挿入する。人手レビュー時にまとめて判断できるようにする。

### 形式

Markdown ファイルの場合（HTML コメント）:

```
<!-- REVIEW-SUGGEST: [RQ-042] AC-003 の受け入れ条件が曖昧。具体的な数値条件を検討 -->
<!-- REVIEW-NIT: [RQ-058] 「ユーザー」と「利用者」の表記揺れ -->
```

### ルール

- `REVIEW-SUGGEST:` / `REVIEW-NIT:` を prefix とする。既存の `TODO` / `FIXME` と区別するための専用 prefix。
- review JSON の finding ID（`[RQ-042]` 等）があれば付与する。無ければ省略可。
- メッセージは review JSON の `message` をそのまま、または要約して記載。
- 該当箇所の **直前行** に挿入する（該当行が特定できない場合はファイル末尾のセクションにまとめる）。
- マーカーは修正ではないため、既存の文面を書き換えない。

## 注意事項

- 1 review に対して fix-requirements は 1 回だけ走る（2 回呼ばれない設計）。
- 修正によって新しい不整合が生まれた場合は次の iteration の review で検出される（それが本ループの目的）。
