---
name: design-loop
description: 「design phase の produce → review → fix → review」の反復ループを最大 max_iterations 回まで回すオーケストレータ。BLOCK 件数が 0 になるか上限到達まで自動で繰り返す。
argument-hint: <docs/requirements/ または個別の要件定義ファイルパス（省略時 docs/requirements/ 全件）、または設計書作成 Issue 番号>
allowed-tools: Bash, Read, Skill
---

# design loop オーケストレータ
> **STATE_DIR の解決（D-03・最初に必ず 1 回）**: `STATE_DIR="$(bash .claude/skills/_common/scripts/state-dir.sh design)"` を実行し、以降の `<STATE_DIR>` はこの絶対パスを指す。`.skills-state/...` の相対パス直書きは禁止（書き手による state 置き場の分裂防止）。


> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

入力: $ARGUMENTS

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4（Iterative Loop）に従う **design phase 専用** オーケストレータです。

**重要: このスキルは `context: fork` を持ちません。** ループ状態の保持と sub-skill 呼び出しの連鎖が main session で完結する必要があるためです（設計ドキュメント「6. orchestrator skill のロジック」参照）。

## 役割

`design` phase の produce / review / fix を反復し、レビュー BLOCK 件数が 0 になるか max_iterations に到達するまで自動で進める。state は `<STATE_DIR>/state.json` に集約。

## ガードレール自動適用（必須・H-5）

`design-guardrails` は description のトリガ語で自動起動するが、本ループは **ガードレール適用を各 sub-skill 呼び出しの前提（必須ステップ）として明示** し、未適用のまま PASS させない。produce=`design-from-requirements` / review=`review-design` / fix=`fix-design` の各 stage で `.claude/skills/design-guardrails/` の以下を必ず適用する:

- `references/negative-patterns.md`（設計の MUST NOT）
- `references/consistency-checklist.md`（文書間整合: 画面↔API↔DB・operationId・コード値4層・状態遷移）
- `references/security-checklist.md`（認可・テナント境界・機微情報・OWASP 観点）

ガードレール未適用で produce/fix を完了扱いにしてはならない（requirements-loop の M-17 と対称）。

## 現在の状態（決定論層で生成）

> **state の出力先（自動・所有リポ集約。手動設定不要）**: `.skills-state/` の出力先・参照先は 各スクリプトが phase から決定論的に解決する（`_common/scripts/_state-root.sh`）。requirements/design は所有リポ `claude-poc-docs` に、implement/integration は実行中の子リポに集約される。起動 CWD に依存しないため、ここで `STATE_ROOT` を手動設定する必要はない（特定の場所へ明示的に上書きしたい場合のみ `export STATE_ROOT=...`）。


!`bash ${CLAUDE_SKILL_DIR}/../_common/scripts/init-state.sh design "$ARGUMENTS"`
> **反復回数の正典**: 上限は `_common/scripts/init-state.sh` の `MAX_ITER` で一元管理（既定値はスクリプトを参照）。loop スキルには回数をハードコードしない。


## 手順

0.-1. **スコープ分割の推奨（U-1）**: 要件全件を一括で回すとループが長時間化する（1 サイクル目実測 約1時間50分）。機能単位（functional/ の 1〜3 ファイル）に引数を絞って複数回に分けて回すことを推奨する。分割した場合、横断整合（コード値・共通部品・共通レイアウト）は最終回の review で全体を対象に確認する。
0. **Phase 0 Research（推奨・任意）**: `docs/requirements/オープン課題.md` に「設計着手前クローズ必須」区分（Q-NF\* / Q-DM\* / Q-EI\* / Q-MIG\* 等）が `open` のまま残っている場合は、`/design-pre-research` を先に実行することを推奨する。未解決 Q-ID が存在するままループに進むと `review-design` で BLOCK になり反復コストが増大する。ただし必須ではないため、ユーザーが「そのまま進める」と指示した場合はこの手順をスキップしてよい。
0.1. **スタック確定ゲート**: `bash .claude/skills/_common/scripts/check-stack-decided.sh` を実行し、exit 1 の場合はループを開始せず ESCALATE 相当として終了する。未確定項目の一覧を人間に提示し、確定表（*-00-stack.md）への記入を依頼する。state.json には `gate: "stack-undecided"` を記録する。
0.5. **要件採択ゲート（ADD-7 / M-6・決定論）**: `bash .claude/skills/_common/scripts/check-adopted.sh docs/requirements`（パス解決ルールに従い、親アンブレラからは `claude-poc-docs/docs/requirements`）を実行し、要件定義書が docs リポジトリの `main`（既定 `origin/main`）にマージ済み（＝採択済み）かつ未マージのローカル変更が無いことを機械的に確認する。exit 1 の場合はループを開始せず、人手レビュー・マージ（採択）を依頼して終了する。state.json には `gate: "requirements-not-adopted"` を記録する。CI（main 契機）では自明のためスキップ可。
0.6. **オープン課題クローズゲート（RC-10・必須）**: `bash .claude/skills/_common/scripts/check-open-issues.sh`（親アンブレラからはパス解決ルールに従い `claude-poc-docs/docs/requirements/オープン課題.md` を対象）を実行し、設計着手前にクローズ必須の課題区分（`Q-NF*` / `Q-DM*` / `Q-EI*` / `Q-MIG*`）が open のまま残っていれば exit 1。その場合はループを開始せず、未クローズ課題の一覧を人間に提示して終了する。state.json には `gate: "open-issues-remaining"` を記録する。
0.7. **確定値反映ゲート（R-02・必須）**: `bash .claude/skills/_common/scripts/check-closed-reflected.sh docs/requirements --gate`（親アンブレラからはパス解決ルールに従い `claude-poc-docs/docs/requirements`）を実行し、クローズ済み課題の確定値が要件本文に未反映（未確定系プレースホルダ残存）なら exit 1。その場合はループを開始せず、採択チェックリスト（docs/process/11-adoption-checklist.md）に沿った反映を人間に依頼して終了する。state.json には `gate: "closed-not-reflected"` を記録する。
0.8. **AC 一意性ゲート（R-01・必須）**: `bash .claude/skills/_common/scripts/check-id-uniqueness.sh docs/requirements --gate`（同上）を実行し、AC の機能内重複・非修飾の曖昧参照があれば exit 1。state.json には `gate: "id-uniqueness"` を記録する。
1. **state を読む**: 上で出力されたパス（`<STATE_DIR>/state.json`）を Read で読み、`stage` / `iteration` / `passed` / `escalated` を取得する。
2. **終了条件を判定**:
   - `passed == true` → 「✅ design PASS」のサマリを表示して終了
   - `escalated == true`（前回上限到達） →
     **再実行検出**: 成果物が修正された可能性があるため、ユーザーに「修正後に再レビューしますか？」と確認する。
     - **Yes**: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/init-state.sh design "$ARGUMENTS" --reset` を実行し、state を再読み込みする。`stage=review` から再開される（produce はスキップ）。以降ループを継続する。
     - **No**: 未解決 BLOCK 一覧を表示して終了。
   - 上記以外 → 次の stage を実行する
3. **stage に応じて分岐**:
   - `produce`: state.extra_args の内容で呼ぶ skill を分岐し、Skill ツールで呼ぶ:
     - extra_args が GitHub Issue 番号（数値のみ。例 `123` / `#123`）の場合: `/design-from-issue` （引数に Issue 番号を渡す。Issue 本文から対象の要件定義書を解決して設計する）
     - それ以外（要件定義パスまたは空）の場合: `/design-from-requirements` （引数は state.extra_args を渡す）
     - **機械ゲート前置（P-11・必須）**: produce 完了後 review に渡す前に、決定論チェック（check-openapi-valid.sh / check-contract.sh / check-db-design-consistency.sh / check-truncation.sh / check-wiring-fields.sh）を実行し、機械検出可能な BLOCK 級の欠陥は produce の一部として即修正してから advance する。review のラウンドを機械検出可能な指摘で消費しない。
     - 完了後: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/advance-state.sh design review`
   - `review`: Skill ツールで次の skill を呼ぶ:
     - `/review-design`
     - 完了後: review skill が生成した review JSON のパス（`<STATE_DIR>/round-N-review.json`）を引数に渡して
       `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/record-review.sh design <review-json-path>`
     - record-review.sh が次の stage（done / fix / escalate）を決めて state に書き込む
     - `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/append-review-summary.sh design <review-json-path>`（レビュー結果.md への追記。review skill 自身は行わない）
   - `fix`: Skill ツールで次の skill を呼ぶ:
     - `/fix-design`
     - 完了後: state.json の `last_review_path` から直前の review JSON パスを取得し、Skill ツールで `/verify-fix <review-json-path>` を呼ぶ
     - verify-fix の出力 JSON を Read し、`all_blocks_addressed` を確認:
       - `true` → `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/advance-state.sh design review`（iteration インクリメント → 次の review へ）
       - `false` → `/fix-design` を再実行（1 回のみ）→ 再度 `/verify-fix` → 結果に関わらず `advance-state.sh design review` で次の review へ進む
   - `done` / `escalate`: 何もせず終了サマリを表示
4. **ループ**: 上記が 1 stage 終わったら、再度 step 1 から繰り返す。`passed == true` か `escalated == true` になるまで自動で回す。

## 終了時の最終サマリ

最後に必ず次のコマンドを実行して結果を表示する:

```bash
bash ${CLAUDE_SKILL_DIR}/../_common/scripts/summarize-state.sh design
```

加えて、PASS の場合は「`design` phase 完了。次フェーズに進めます」、ESCALATE の場合は「上限到達。未解決 BLOCK を人手レビューしてください: <一覧>」と明示する。

PASS の場合はさらに次を実行する:
- **RTM 骨格の前倒し生成（P-15）**: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/generate-rtm-skeleton.sh docs/requirements docs/design docs/test/RTM.md`（パス解決ルールに従い親アンブレラからは claude-poc-docs/ を前置）。以後 TC/Issue# 列は製造、IT 列は結合テスト工程が埋める。
- **ループ計測の記録（P-17）**: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/loop-metrics.sh "$(bash ${CLAUDE_SKILL_DIR}/../_common/scripts/state-dir.sh design)" --out docs/process/metrics/design-loop-<日付>.md`（--out はパス解決ルールに従い docs リポ側に置く。phase ディレクトリ直接指定を受理する・D-04）。
- **採択レビュー用ビューの案内（D-06）**: PASS サマリに「次: `/humanize-design` で採択レビュー用ビューを生成 → 人手採択（docs/process/11-adoption-checklist.md）」を必ず明示する（開発フロー 3.5）。

## 注意事項

- 必ず冒頭で state を読み、stage に応じて分岐する。**state を無視して何かを書き始めない**。
- sub-skill 呼び出しは **Skill ツール** で行う（Bash で直接 .md を実行しない）。
- review skill が JSON を出さなかった、または不正だった場合は orchestrator を即停止し、ユーザーに報告する。
- fix skill は BLOCK + SUGGEST + NIT を対象に修正する。NIT も極力対応し、スキップした指摘のみレビューマーカーを残す。


## 参考

- 設計: [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md)
- state JSON スキーマ: 設計ドキュメントの「4. state JSON スキーマ」
- review JSON スキーマ: 設計ドキュメントの「5. review JSON スキーマ」
