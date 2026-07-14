---
name: implement-loop
description: TDD ファーストで「テスト設計 → テストコード生成 → 実装 → review → fix」の反復ループを最大 max_iterations 回まで回すオーケストレータ。テストを実装より先に作成し、BLOCK 件数が 0 になるか上限到達まで自動で繰り返す。
argument-hint: [<repo: frontend|backend|batch|e2e>] <GitHub Issue 番号>
allowed-tools: Bash, Read, Skill
---

# implement loop オーケストレータ（TDD ファースト）

入力: $ARGUMENTS

> **親アンブレラからの複数リポジトリ対応（第1引数でリポジトリ指定）**: 対象子リポジトリのディレクトリ内で実行している場合（CI 実行時を含む）は従来どおり `<Issue番号>` の1引数で呼ぶ。親アンブレラ（claude-poc-rules）直下から複数リポジトリをまたいで呼びたい場合は `<repo> <Issue番号>`（例: `frontend 123`）の2引数で呼ぶ。`repo` は `frontend` / `backend` / `batch` / `e2e` のいずれか。判定・ディスパッチ手順は下記「現在の状態」節を参照。

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4（Iterative Loop）に従う **implement phase 専用** オーケストレータです。

**TDD ファースト**: テスト設計（`/test-design-from-issue draft`）とテストコード生成（`/unit-test-from-design pre-write`）を実装（`/implement-from-issue`）より先に実行します。テストが先に存在し、実装がテストを通す形でコードを書きます。

**重要: このスキルは `context: fork` を持ちません。** ループ状態の保持と sub-skill 呼び出しの連鎖が main session で完結する必要があるためです（設計ドキュメント「6. orchestrator skill のロジック」参照）。

## 役割

`implement` phase の test-design / test-write / produce / review / fix を反復し、レビュー BLOCK 件数が 0 になるか max_iterations に到達するまで自動で進める。state は `.skills-state/implement/state.json` に集約。

## TDD フロー概要

```
1. test-design  : /test-design-from-issue draft  → TC-XXX マトリクスを設計書・AC から先出し
2. test-write   : /unit-test-from-design pre-write → テストコードを先に生成（実装なしで失敗状態が正常）
3. produce      : /implement-from-issue           → テストが通るように実装 + 品質ゲート
4. review       : /review-implementation          → コードレビュー + 品質ゲート確認
5. fix          : /fix-implementation             → BLOCK 解消（review → fix → review を繰り返す）
```

## 現在の状態（決定論層で生成）

> **state の出力先（自動・所有リポ集約。手動設定不要）**: `.skills-state/` の出力先・参照先は 各スクリプトが phase から決定論的に解決する（`_common/scripts/_state-root.sh`）。requirements/design は所有リポ `claude-poc-docs` に、implement/integration は実行中の子リポに集約される。起動 CWD に依存しないため、ここで `STATE_ROOT` を手動設定する必要はない（特定の場所へ明示的に上書きしたい場合のみ `export STATE_ROOT=...`）。


**state 初期化（必ず Bash ツールで実行する。`!`command`` 形式のインライン実行は使わない — Windows 環境で承認不能な別経路の許可チェックにかかり停止するため）**:

```bash
bash ${CLAUDE_SKILL_DIR}/../_common/scripts/init-state-with-dispatch.sh implement $ARGUMENTS
```

> **反復回数の正典**: 上限は `_common/scripts/init-state.sh` の `MAX_ITER` で一元管理（既定値はスクリプトを参照）。loop スキルには回数をハードコードしない。

> **ディスパッチ判定（必須・最初に必ず確認）**: 上記コマンドの出力1行目 `DISPATCH_REPO_DIR=<dir または 空>` を確認する。
> - **`<dir>` が入っている場合**（親アンブレラから `<repo> <Issue番号>` の2引数で呼ばれ、対象リポジトリのディレクトリが特定できた）: ここで**必ず** Bash ツールで実際に `cd <dir>` を実行する（このスクリプト内部の cd は本コマンドのサブシェルにしか効かず、以降の Claude 自身の操作には引き継がれないため）。cd 後、Skill ツールで `/implement-loop <Issue番号>`（repo を除いた残りの引数）を呼び直し、**本ファイルのこれ以降の手順は実行しない**（呼び直した先で state 初期化からやり直される）。
> - **空の場合**: 現在のカレントディレクトリが対象リポジトリであるとみなし（CI 実行時・子リポジトリ内で直接呼んだ場合はこちら）、そのまま以下の手順を続ける。


## 手順

1. **state を読む**: 上で出力されたパス（`.skills-state/implement/state.json`）を Read で読み、`stage` / `iteration` / `passed` / `escalated` を取得する。

2. **TDD ステージ補正（初回実行時のみ）**: `stage == "produce"` かつ `iteration == 1` かつ `history` の長さが 1（"init" エントリのみ）の場合、TDD フローのために stage を `test-design` に書き換える。次の Bash を実行し、出力を確認する。その後 state を再 Read して以降の判断に使う:

   ```bash
   python3 -c "
   import json, datetime, os
   p = '.skills-state/implement/state.json'
   with open(p) as f: s = json.load(f)
   if s['stage'] == 'produce' and s['iteration'] == 1 and len(s.get('history', [])) == 1:
       s['stage'] = 'test-design'
       s['updated_at'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
       # D-08: アトミック書き込み（tmp へ書き fsync 後 rename。途中切断による不正 JSON を防ぐ）
       tmp = p + '.tmp'
       with open(tmp, 'w') as f:
           json.dump(s, f, ensure_ascii=False, indent=2)
           f.flush(); os.fsync(f.fileno())
       os.replace(tmp, p)
       print('TDD: initial stage set to test-design')
   else:
       print('TDD: no override needed, stage=' + s['stage'])
   "
   ```

3. **終了条件を判定**:
   - `passed == true` → 「✅ implement PASS」のサマリを表示して終了
   - `escalated == true`（前回上限到達） →
     **再実行検出**: 成果物が修正された可能性があるため、ユーザーに「修正後に再レビューしますか？」と確認する。
     - **Yes**: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/init-state.sh implement "$ARGUMENTS" --reset` を実行し、state を再読み込みする。`stage=review` から再開される（produce はスキップ）。以降ループを継続する。
     - **No**: 未解決 BLOCK 一覧を表示して終了。
   - 上記以外 → 次の stage を実行する

4. **stage に応じて分岐**:

   - `test-design`: Skill ツールで `/test-design-from-issue $ARGUMENTS draft` を呼ぶ
     - 設計書（AC-XXX・実装内容項目）からテストケース（TC-XXX）を設計し、`docs/test/単体テストマトリクス.md` のドラフトを生成する
     - 実コードとの突合・ハードゲートはスキップ（draft モード）
     - 完了後: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/advance-state.sh implement test-write`

   - `test-write`: Skill ツールで `/unit-test-from-design pre-write $ARGUMENTS` を呼ぶ
     - `pre-write` モード: TC-XXX マトリクスと設計書をもとにテストコードを**先に**生成する
     - **この時点では実装コードが存在しないため、テストはコンパイルエラーまたは実行失敗が正常状態**。テストを通すための実装は次の `produce` 段で行う
     - テストを実行したり失敗を修正しようとしてはならない（実装前の失敗は期待どおり）
     - 完了後: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/advance-state.sh implement produce`

   - `produce`: まず **設計採択ゲート（M-6・決定論）** として `bash .claude/skills/_common/scripts/check-adopted.sh docs/design`（パス解決ルールに従い親アンブレラからは `claude-poc-docs/docs/design`）を実行し、設計書が docs リポジトリの `main`（既定 `origin/main`）にマージ済み（採択済み）であることを機械的に確認する。exit 1 の場合は produce を行わず、人手の採択（PR マージ）を依頼して終了する。次に Skill ツールで `/implement-from-issue $ARGUMENTS` を呼ぶ（引数は state.extra_args を渡す）
     - テストコードは `test-write` 段で既に生成済みのため、`/implement-from-issue` 内の手順 3.5（テスト設計ドラフト）は既存マトリクスを確認するだけでよく、テストコードの再生成は行わない
     - 手順 4（実装）では、`test-write` 段で書かれたテストが通るようにプロダクションコードを書く（Red → Green）
     - 手順 5 の品質ゲートでテストを実行し、全テストが通ることを確認する
     - **機械ゲート前置（P-11・必須）**: review へ advance する前に、品質ゲート（型チェック・lint・format・単体テスト・カバレッジ閾値）を produce 内で全緑にする。機械検出可能な欠陥（型エラー・lint 違反・カバレッジ未達）が残ったまま review に渡してはならない（1 サイクル目は round 6〜12 をこの種の指摘で消費した）。review は設計整合・セキュリティ・内容品質に集中させる。
     - 完了後: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/advance-state.sh implement review`

   - `review`: Skill ツールで `/review-implementation` を呼ぶ
     - 完了後: review skill が生成した review JSON のパス（`.skills-state/implement/round-N-review.json`）を引数に渡して
       `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/record-review.sh implement <review-json-path>`
     - record-review.sh が次の stage（done / fix / escalate）を決めて state に書き込む
     - Issue 番号を state（extra_args）またはブランチ名 `feature/issue-<N>` から取得し、
       `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/append-review-summary.sh implement <review-json-path> --issue <ISSUE>`
       （レビュー結果.md への追記。review skill 自身は行わない）
     - 追記後、feature ブランチへ commit/push:
       ```bash
       git add "docs/test/レビュー結果/implement-issue-<ISSUE>.md"
       git commit -m "docs(review): implement round <N> レビュー結果 (#<ISSUE>)" || true
       git push || true
       ```

   - `fix`: Skill ツールで `/fix-implementation` を呼ぶ
     - 完了後: state.json の `last_review_path` から直前の review JSON パスを取得し、Skill ツールで `/verify-fix <review-json-path>` を呼ぶ
     - verify-fix の出力 JSON を Read し、`all_blocks_addressed` を確認:
       - `true` → `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/advance-state.sh implement review`（iteration インクリメント → 次の review へ）
       - `false` → `/fix-implementation` を再実行（1 回のみ）→ 再度 `/verify-fix` → 結果に関わらず `advance-state.sh implement review` で次の review へ進む

   - `done` / `escalate`: 何もせず終了サマリを表示

5. **ループ**: 上記が 1 stage 終わったら、再度 step 1 から繰り返す。`passed == true` か `escalated == true` になるまで自動で回す。

## 終了時の最終サマリ

最後に必ず次のコマンドを実行して結果を表示する:

```bash
bash ${CLAUDE_SKILL_DIR}/../_common/scripts/summarize-state.sh implement
```

加えて、PASS の場合は「`implement` phase 完了。次フェーズに進めます」、ESCALATE の場合は「上限到達。未解決 BLOCK を人手レビューしてください: <一覧>」と明示する。

PASS の場合はさらに **ループ計測の記録（P-17）**: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/loop-metrics.sh <state-root> --out docs/process/metrics/implement-loop-<日付>.md`（state-root はスクリプトの仕様に従う）を実行する。

## 注意事項

- 必ず冒頭で state を読み、stage に応じて分岐する。**state を無視して何かを書き始めない**。
- **実装は必ず本 `implement-loop` 経由で起動し、state を初期化する（D-16）**。`implement-loop` を介さずに `implement-from-issue` / `review-implementation` を単独起動した場合、state が初期化されておらず iteration 管理・終了条件・採択ゲートが効かないため **無効**とする。**state 不在のまま実行された review は無効**であり、orchestrator はその結果を採用しない。state は必ずスクリプト経由で生成・更新し、手編集しない。
- sub-skill 呼び出しは **Skill ツール** で行う（Bash で直接 .md を実行しない）。slash コマンドはコードフェンス内に書かない（Bash で誤実行されないよう地の文で参照する＝D-13）。
- review skill が JSON を出さなかった、または不正だった場合は orchestrator を即停止し、ユーザーに報告する。
- fix skill は BLOCK + SUGGEST + NIT を対象に修正する。NIT も極力対応し、スキップした指摘のみレビューマーカーを残す。
- `test-write` stage でテストがコンパイルエラー・実行失敗になることは**正常**。実装コードが存在しないため。
- implement phase では produce skill (`/implement-from-issue`) が内部で品質ゲート（UT / 静的解析）を Pattern 2 で並列実行する（E2E は対象外・AWS 環境構築後の別工程）。
- review-implementation は「コード差分のレビュー」+「品質ゲートが緑であることの確認」を兼ねる。
- fix-implementation は同じ feature ブランチに追加コミットし、既存 PR を更新する（新規 PR は作らない）。

## 参考

- 設計: [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md)
- state JSON スキーマ: 設計ドキュメントの「4. state JSON スキーマ」
- review JSON スキーマ: 設計ドキュメントの「5. review JSON スキーマ」
