---
name: requirements-loop
description: 「requirements phase の produce → review → fix → review」の反復ループを最大 max_iterations 回まで回すオーケストレータ。BLOCK 件数が 0 になるか上限到達まで自動で繰り返す。
argument-hint: <要件素材ファイル/メモのパス>
allowed-tools: Bash, Read, Skill
---

# requirements loop オーケストレータ
> **STATE_DIR の解決（D-03・最初に必ず 1 回）**: `STATE_DIR="$(bash .claude/skills/_common/scripts/state-dir.sh requirements)"` を実行し、以降の `<STATE_DIR>` はこの絶対パスを指す。`.skills-state/...` の相対パス直書きは禁止（書き手による state 置き場の分裂防止）。


入力: $ARGUMENTS

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4（Iterative Loop）に従う **requirements phase 専用** オーケストレータです。

**重要: このスキルは `context: fork` を持ちません。** ループ状態の保持と sub-skill 呼び出しの連鎖が main session で完結する必要があるためです（設計ドキュメント「6. orchestrator skill のロジック」参照）。

## 役割

`requirements` phase の produce / review / fix を反復し、レビュー BLOCK 件数が 0 になるか max_iterations に到達するまで自動で進める。state は `<STATE_DIR>/state.json` に集約。

## ガードレール自動適用（M-17・必須）

本ループの **produce / review / fix の各 stage で `requirements-guardrails` スキルを必ず自動適用する**（人手で `/requirements-guardrails` を打つ運用に依存しない）。

- `produce`（`/requirements-from-input`）実行時: `requirements-guardrails` の MUST NOT（カテゴリ A〜D）・データ/IF 最低ライン・非機能要求値テンプレ・文書間整合チェックを適用しながら生成する。
- `review`（`/review-requirements`）実行時: `requirements-guardrails/references/negative-patterns.md`・`consistency-checklist.md` の観点（`data-chain` / `ext-failure-flow` / `row-level-authz` を含む新観点）に照らして findings を作る。
- `fix`（`/fix-requirements`）実行時: 修正後に `consistency-checklist.md` の文書間整合（ステータス遷移・画面遷移・用語）を再確認する。

`requirements-guardrails` は description のトリガ語により自動起動するが、本ループは **ガードレール適用を各 sub-skill 呼び出しの前提（必須ステップ）として明示**し、未適用のまま PASS させない。

## 現在の状態（決定論層で生成）

> **state の出力先（自動・所有リポ集約。手動設定不要）**: `.skills-state/` の出力先・参照先は 各スクリプトが phase から決定論的に解決する（`_common/scripts/_state-root.sh`）。requirements/design は所有リポ `claude-poc-docs` に、implement/integration は実行中の子リポに集約される。起動 CWD に依存しないため、ここで `STATE_ROOT` を手動設定する必要はない（特定の場所へ明示的に上書きしたい場合のみ `export STATE_ROOT=...`）。


!`bash ${CLAUDE_SKILL_DIR}/../_common/scripts/init-state.sh requirements "$ARGUMENTS"`
> **反復回数の正典**: 上限は `_common/scripts/init-state.sh` の `MAX_ITER` で一元管理（既定値はスクリプトを参照）。loop スキルには回数をハードコードしない。


## 手順

1. **state を読む**: 上で出力されたパス（`<STATE_DIR>/state.json`）を Read で読み、`stage` / `iteration` / `passed` / `escalated` を取得する。
2. **終了条件を判定**:
   - `passed == true` → 「✅ requirements PASS」のサマリを表示して終了
   - `escalated == true`（前回上限到達） →
     **再実行検出**: 成果物が修正された可能性があるため、ユーザーに「修正後に再レビューしますか？」と確認する。
     - **Yes**: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/init-state.sh requirements "$ARGUMENTS" --reset` を実行し、state を再読み込みする。`stage=review` から再開される（produce はスキップ）。以降ループを継続する。
     - **No**: 未解決 BLOCK 一覧を表示して終了。
   - 上記以外 → 次の stage を実行する
3. **stage に応じて分岐**:
   - `produce`: Skill ツールで次の skill を呼ぶ:
     - `/requirements-from-input` （引数は state.extra_args を渡す）
     - 完了後: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/advance-state.sh requirements review`
   - `review`: Skill ツールで次の skill を呼ぶ:
     - `/review-requirements`
     - 完了後: review skill が生成した review JSON のパス（`<STATE_DIR>/round-N-review.json`）を引数に渡して
       `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/record-review.sh requirements <review-json-path>`
     - record-review.sh が次の stage（done / fix / escalate）を決めて state に書き込む
     - `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/append-review-summary.sh requirements <review-json-path>`（レビュー結果.md への追記。review skill 自身は行わない）
   - `fix`: Skill ツールで次の skill を呼ぶ:
     - `/fix-requirements`
     - 完了後: state.json の `last_review_path` から直前の review JSON パスを取得し、Skill ツールで `/verify-fix <review-json-path>` を呼ぶ
     - verify-fix の出力 JSON を Read し、`all_blocks_addressed` を確認:
       - `true` → `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/advance-state.sh requirements review`（iteration インクリメント → 次の review へ）
       - `false` → `/fix-requirements` を再実行（1 回のみ）→ 再度 `/verify-fix` → 結果に関わらず `advance-state.sh requirements review` で次の review へ進む
   - `done` / `escalate`: 何もせず終了サマリを表示
4. **ループ**: 上記が 1 stage 終わったら、再度 step 1 から繰り返す。`passed == true` か `escalated == true` になるまで自動で回す。

## 終了時の最終サマリ

最後に必ず次のコマンドを実行して結果を表示する:

```bash
bash ${CLAUDE_SKILL_DIR}/../_common/scripts/summarize-state.sh requirements
```

加えて、PASS の場合は「`requirements` phase 完了。次フェーズに進めます」、ESCALATE の場合は「上限到達。未解決 BLOCK を人手レビューしてください: <一覧>」と明示する。

PASS の場合はさらに **ループ計測の記録（P-17）**: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/loop-metrics.sh "$(bash ${CLAUDE_SKILL_DIR}/../_common/scripts/state-dir.sh requirements)" --out docs/process/metrics/requirements-loop-<日付>.md`（--out はパス解決ルールに従い docs リポ側に置く）を実行する。

PASS 後の採択（人手）は `docs/process/11-adoption-checklist.md` に従う: design-pre-research による Q クローズ → 確定値の本文反映 → `check-closed-reflected` / `check-id-uniqueness` / `check-open-issues` 全緑 → docs main へコミット（R-02/R-05）。

## 注意事項

- 必ず冒頭で state を読み、stage に応じて分岐する。**state を無視して何かを書き始めない**。
- sub-skill 呼び出しは **Skill ツール** で行う（Bash で直接 .md を実行しない）。
- review skill が JSON を出さなかった、または不正だった場合は orchestrator を即停止し、ユーザーに報告する。
- fix skill は BLOCK + SUGGEST + NIT を対象に修正する。NIT も極力対応し、スキップした指摘のみレビューマーカーを残す。


## 参考

- 設計: [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md)
- state JSON スキーマ: 設計ドキュメントの「4. state JSON スキーマ」
- review JSON スキーマ: 設計ドキュメントの「5. review JSON スキーマ」
