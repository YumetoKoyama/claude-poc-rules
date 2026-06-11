---
name: design-loop
description: 「design phase の produce → review → fix → review」の反復ループを最大 max_iterations 回まで回すオーケストレータ。BLOCK 件数が 0 になるか上限到達まで自動で繰り返す。
argument-hint: <docs/requirements/ または個別の要件定義ファイルパス（省略時 docs/requirements/ 全件）、または設計書作成 Issue 番号>
allowed-tools: Bash, Read, Skill
---

# design loop オーケストレータ

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

入力: $ARGUMENTS

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4（Iterative Loop）に従う **design phase 専用** オーケストレータです。

**重要: このスキルは `context: fork` を持ちません。** ループ状態の保持と sub-skill 呼び出しの連鎖が main session で完結する必要があるためです（設計ドキュメント「6. orchestrator skill のロジック」参照）。

## 役割

`design` phase の produce / review / fix を反復し、レビュー BLOCK 件数が 0 になるか max_iterations に到達するまで自動で進める。state は `.skills-state/design/state.json` に集約。

## 現在の状態（決定論層で生成）

!`bash ${CLAUDE_SKILL_DIR}/../_common/scripts/init-state.sh design "$ARGUMENTS" 3`

## 手順

0. **スタック確定ゲート**: `bash .claude/skills/_common/scripts/check-stack-decided.sh` を実行し、exit 1 の場合はループを開始せず ESCALATE 相当として終了する。未確定項目の一覧を人間に提示し、確定表（*-00-stack.md）への記入を依頼する。state.json には `gate: "stack-undecided"` を記録する。
1. **state を読む**: 上で出力されたパス（`.skills-state/design/state.json`）を Read で読み、`stage` / `iteration` / `passed` / `escalated` を取得する。
2. **終了条件を判定**:
   - `passed == true` → 「✅ design PASS」のサマリを表示して終了
   - `escalated == true` → 未解決 BLOCK 一覧を表示して人手レビューへ
   - 上記以外 → 次の stage を実行する
3. **stage に応じて分岐**:
   - `produce`: state.extra_args の内容で呼ぶ skill を分岐し、Skill ツールで呼ぶ:
     - extra_args が GitHub Issue 番号（数値のみ。例 `123` / `#123`）の場合: `/design-from-issue` （引数に Issue 番号を渡す。Issue 本文から対象の要件定義書を解決して設計する）
     - それ以外（要件定義パスまたは空）の場合: `/design-from-requirements` （引数は state.extra_args を渡す）
     - 完了後: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/advance-state.sh design review`
   - `review`: Skill ツールで次の skill を呼ぶ:
     - `/review-design`
     - 完了後: review skill が生成した review JSON のパス（`.skills-state/design/round-N-review.json`）を引数に渡して
       `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/record-review.sh design <review-json-path>`
     - record-review.sh が次の stage（done / fix / escalate）を決めて state に書き込む
   - `fix`: Skill ツールで次の skill を呼ぶ:
     - `/fix-design`
     - 完了後: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/advance-state.sh design review`（iteration が自動でインクリメントされる）
   - `done` / `escalate`: 何もせず終了サマリを表示
4. **ループ**: 上記が 1 stage 終わったら、再度 step 1 から繰り返す。`passed == true` か `escalated == true` になるまで自動で回す。

## 終了時の最終サマリ

最後に必ず次のコマンドを実行して結果を表示する:

```bash
bash ${CLAUDE_SKILL_DIR}/../_common/scripts/summarize-state.sh design
```

加えて、PASS の場合は「`design` phase 完了。次フェーズに進めます」、ESCALATE の場合は「上限到達。未解決 BLOCK を人手レビューしてください: <一覧>」と明示する。

## 注意事項

- 必ず冒頭で state を読み、stage に応じて分岐する。**state を無視して何かを書き始めない**。
- sub-skill 呼び出しは **Skill ツール** で行う（Bash で直接 .md を実行しない）。
- review skill が JSON を出さなかった、または不正だった場合は orchestrator を即停止し、ユーザーに報告する。
- fix skill は BLOCK + SUGGEST を対象に修正する。NIT には触らない（review skill 側で対象外）。


## 参考

- 設計: [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md)
- state JSON スキーマ: 設計ドキュメントの「4. state JSON スキーマ」
- review JSON スキーマ: 設計ドキュメントの「5. review JSON スキーマ」
