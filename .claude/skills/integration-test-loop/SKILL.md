---
name: integration-test-loop
description: 「integration-test phase の produce → review → fix → review」の反復ループを最大 max_iterations 回まで回すオーケストレータ。結合テストを設計・実施し、失敗原因が実装側なら fix、設計側なら ESCALATE する。BLOCK（失敗）件数が 0 になるか上限到達まで自動で繰り返す。
argument-hint: <フィーチャ名 または 結合テスト Issue 番号>
allowed-tools: Bash, Read, Skill
---

# integration-test loop オーケストレータ

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は、読み取り入力（要件・設計）は **docs リポジトリ（claude-poc-docs）ルート相対**、書き込み出力（結合テストマトリクス・RTM・結合テストコード）は **own リポジトリ（実装リポ）のワーキングツリー直下**。
> - docs をカレントで実行ならそのまま、親アンブレラからなら docs 読み取りパスに `claude-poc-docs/` を前置、CI で workflow が追加チェックアウトした docs があればそのパスを使う。

入力: $ARGUMENTS

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4（Iterative Loop）に従う **integration-test phase 専用** オーケストレータです（S3）。

**重要: このスキルは `context: fork` を持ちません。** ループ状態の保持と sub-skill 呼び出しの連鎖が main session で完結する必要があるためです（設計ドキュメント「6. orchestrator skill のロジック」参照）。

> **製造との分離**: 結合テストはフィーチャ単位で複数 Issue をまたぐため、製造（`implement-loop`）では設計・実施とも行わない。本ループは、対象フィーチャの構成 Issue 群が `main` に組み上がった後に独立工程として起動する（E2E と同様の切り分け）。製造の各 Issue からは呼ばない。

## 役割

`integration-test` phase の produce / review / fix を反復し、結合テストの失敗（BLOCK）が 0 になるか max_iterations に到達するまで自動で進める。state は `.skills-state/integration/state.json` に集約。

- **produce**: `/integration-test-from-design` が結合テストマトリクス（IT-XXX）を設計し、@SpringBootTest + Testcontainers で実施、契約スモーク（ログイン→主要画面データ取得を実 HTTP で疎通）と `check-api-contract.sh`（BE 実レスポンスの OpenAPI 適合）まで行い、RTM の IT 列を更新する。
- **review**: 結合テスト・契約スモーク・契約適合検証の **失敗原因を「実装側」か「設計側」かに判定**する（後述「失敗原因の切り分け」）。
- **fix**: **実装側の失敗のみ** `/fix-implementation` 相当の方針で修正する（同じ feature/IT ブランチに追加コミット）。**設計側の不整合（設計書が誤り・契約の供給元フィールド欠落等）は修正せず ESCALATE** し、設計フェーズへ差し戻す。

## 現在の状態（決定論層で生成）

> **state の出力先（自動・所有リポ集約。手動設定不要）**: `.skills-state/` の出力先・参照先は 各スクリプトが phase から決定論的に解決する（`_common/scripts/_state-root.sh`）。requirements/design は所有リポ `claude-poc-docs` に、implement/integration は実行中の子リポに集約される。起動 CWD に依存しないため、ここで `STATE_ROOT` を手動設定する必要はない（特定の場所へ明示的に上書きしたい場合のみ `export STATE_ROOT=...`）。


!`bash ${CLAUDE_SKILL_DIR}/../_common/scripts/init-state.sh integration "$ARGUMENTS"`
> **反復回数の正典**: 上限は `_common/scripts/init-state.sh` の `MAX_ITER` で一元管理（既定値はスクリプトを参照）。loop スキルには回数をハードコードしない。


> 注: `integration` phase の state 初期化・iteration 境界・終了条件は `_common/scripts/init-state.sh` / `advance-state.sh` / `record-review.sh` が担保する（`integration` phase 対応は提供済み。設計側カテゴリ `integration_design` の BLOCK は `record-review.sh` が iteration に関わらず即 escalate する＝環境変数 `ESCALATE_CATEGORIES` で変更可）。state は必ずスクリプト経由で生成・更新し、手編集しない。

## 手順

0. **前提ゲート（結合点の成立確認）**: 対象フィーチャの構成 Issue 群が採択・マージされ、結合の相手コンポーネントが揃っているか確認する。未マージの依存がある場合はループを開始せず終了し、対象 Issue のマージを依頼する。state.json には `gate: "components-not-ready"` を記録する。
1. **state を読む**: 上で出力されたパス（`.skills-state/integration/state.json`）を Read で読み、`stage` / `iteration` / `passed` / `escalated` を取得する。
2. **終了条件を判定**:
   - `passed == true` → 「✅ integration-test PASS」のサマリを表示して終了
   - `escalated == true`（前回上限到達） →
     **再実行検出**: 成果物が修正された可能性があるため、ユーザーに「修正後に再レビューしますか？」と確認する。
     - **Yes**: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/init-state.sh integration "$ARGUMENTS" --reset` を実行し、state を再読み込みする。`stage=review` から再開される（produce はスキップ）。以降ループを継続する。
     - **No**: 未解決 BLOCK 一覧を表示して終了。
   - 上記以外 → 次の stage を実行する
3. **stage に応じて分岐**:
   - `produce`: Skill ツールで `/integration-test-from-design`（引数は state.extra_args を渡す）を呼ぶ。結合テストマトリクス（IT-XXX）設計・@SpringBootTest + Testcontainers 実施・契約スモーク・`check-api-contract.sh`・RTM 更新まで行う。
     - 完了後: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/advance-state.sh integration review`
   - `review`: 結合テスト結果・契約スモーク・契約適合検証の失敗を集計し、**失敗原因を「実装側」「設計側」に切り分けて** review JSON を生成する（後述）。
     - 生成した review JSON を `.skills-state/integration/round-<N>-review.json` に書き出し、`bash .claude/skills/_common/scripts/validate-review-json.sh <path>` で検証する。
     - 完了後: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/record-review.sh integration <review-json-path>` を実行し、次の stage（done / fix / escalate）を決めさせる。
     - `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/append-review-summary.sh integration <review-json-path>`（※ integration 用レビュー結果.md を生成。現在は integration phase 用の出力先未定義のため、将来対応でも可）
   - `fix`: **実装側 BLOCK のみ**を対象に修正する。Skill ツールで `/fix-implementation` を呼ぶ（または同等の実装修正を本セッションで行う）。修正後、結合テスト・契約スモーク・`check-api-contract.sh` を再実行して緑を確認し、IT マトリクス・RTM を整合させる。
     - **設計側 BLOCK が含まれる場合は修正せず ESCALATE**（`record-review.sh` の判定で `escalate` になる。設計書を本工程で書き換えない）。
     - 完了後: state.json の `last_review_path` から直前の review JSON パスを取得し、Skill ツールで `/verify-fix <review-json-path>` を呼ぶ
     - verify-fix の出力 JSON を Read し、`all_blocks_addressed` を確認:
       - `true` → `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/advance-state.sh integration review`（iteration インクリメント → 次の review へ）
       - `false` → fix を再実行（1 回のみ）→ 再度 `/verify-fix` → 結果に関わらず `advance-state.sh integration review` で次の review へ進む
   - `done` / `escalate`: 何もせず終了サマリを表示
4. **ループ**: 上記が 1 stage 終わったら、再度 step 1 から繰り返す。`passed == true` か `escalated == true` になるまで自動で回す。

## 失敗原因の切り分け（review 段の核心）

各失敗を **実装側 / 設計側** に分類し、category を割り当てる。

| 分類 | category（severity=BLOCK） | 例 | ループの扱い |
| --- | --- | --- | --- |
| **実装側** | `integration_impl` | テナントフィルタが UPDATE/DELETE/COUNT に漏れている、`@Version`/`@Lock` 未付与で競合が 409 にならない、トランザクション境界の誤り、Jackson の JSON 名乖離（`@JsonProperty` 漏れ）、CORS/Cookie 設定が設計値と不一致 | **fix**（実装を修正） |
| **設計側** | `integration_design` | OpenAPI スキーマに供給元フィールドが無い（契約スモークで必須フィールドが取得不能＝dead-field の真因が設計）、IT が要求する API が設計に存在しない、認可設計の行が欠落、設計の制約が DB と矛盾 | **ESCALATE**（設計フェーズへ差し戻し。本工程では直さない） |

- 失敗が無ければ findings は空（または NIT のみ）で overall=PASS。
- 実装側・設計側が混在する場合は、設計側 BLOCK が 1 件でも残る限り **ESCALATE** とする（実装側だけ直しても設計欠落は埋まらないため）。
- 契約スモークの失敗（必須フィールドが空・取得不能）は、**供給元が API に存在しないなら設計側**、**存在するのに実装が使っていない/握り潰しているなら実装側（`integration_impl`）** に切り分ける。

## 終了時の最終サマリ

最後に必ず次のコマンドを実行して結果を表示する:

```bash
bash ${CLAUDE_SKILL_DIR}/../_common/scripts/summarize-state.sh integration
```

加えて、PASS の場合は「`integration-test` phase 完了。`check-test-matrix.sh ... integration` 通過・契約スモーク成立」、ESCALATE の場合は「上限到達または設計側差し戻し。未解決 BLOCK を人手レビューしてください（設計側は設計フェーズへ）: <一覧>」と明示する。

PASS の場合はさらに **ループ計測の記録（P-17）**: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/loop-metrics.sh <state-root> --out docs/process/metrics/integration-loop-<日付>.md`（state-root はスクリプトの仕様に従う）を実行する。

## 注意事項

- 必ず冒頭で state を読み、stage に応じて分岐する。**state を無視して何かを書き始めない**。
- **本ループ経由で起動し state を初期化する**。loop を介さず `integration-test-from-design` を単独起動した場合、iteration 管理・終了条件・差し戻し判定が効かない（製造の implement-loop と同じ D-16 の原則）。
- sub-skill 呼び出しは **Skill ツール** で行う（Bash で直接 .md を実行しない）。slash コマンドはコードフェンス内に書かない（Bash 誤実行防止＝D-13）。
- review が JSON を出さなかった、または不正だった場合は orchestrator を即停止し、ユーザーに報告する。
- **設計側の不整合（`integration_design`）は本工程で修正しない**。設計書（`docs/design/`）を書き換えず、ESCALATE して設計フェーズの採択ループへ戻す。
- 単体テスト（TC）は製造の責務、E2E はさらに上位の別工程。本ループは結合（IT）と契約スモークのみを扱う。

## 参考

- 工程本体: [integration-test-from-design](../integration-test-from-design/SKILL.md)
- 設計: [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md)
- state JSON スキーマ: 設計ドキュメントの「4. state JSON スキーマ」
- review JSON スキーマ: 設計ドキュメントの「5. review JSON スキーマ」
