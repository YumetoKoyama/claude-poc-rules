---
name: implement-loop
description: 「implement phase の produce → review → fix → review」の反復ループを最大 max_iterations 回まで回すオーケストレータ。BLOCK 件数が 0 になるか上限到達まで自動で繰り返す。
disable-model-invocation: true
argument-hint: <GitHub Issue 番号>
allowed-tools: Bash, Read, SlashCommand
---

# implement loop オーケストレータ

入力: $ARGUMENTS

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4（Iterative Loop）に従う **implement phase 専用** オーケストレータです。

**重要: このスキルは `context: fork` を持ちません。** ループ状態の保持と sub-skill 呼び出しの連鎖が main session で完結する必要があるためです（設計ドキュメント「6. orchestrator skill のロジック」参照）。

## 役割

`implement` phase の produce / review / fix を反復し、レビュー BLOCK 件数が 0 になるか max_iterations に到達するまで自動で進める。state は `.skills-state/implement/state.json` に集約。

## 現在の状態（決定論層で生成）

!`bash ${CLAUDE_SKILL_DIR}/../_common/scripts/init-state.sh implement "$ARGUMENTS" 3`

## 手順

1. **state を読む**: 上で出力されたパス（`.skills-state/implement/state.json`）を Read で読み、`stage` / `iteration` / `passed` / `escalated` を取得する。
2. **終了条件を判定**:
   - `passed == true` → 「✅ implement PASS」のサマリを表示して終了
   - `escalated == true` → 未解決 BLOCK 一覧を表示して人手レビューへ
   - 上記以外 → 次の stage を実行する
3. **stage に応じて分岐**:
   - `produce`: 次の SlashCommand を呼ぶ:
     - `/implement-from-issue` （引数は state.extra_args を渡す）
     - 完了後: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/advance-state.sh implement review`
   - `review`: 次の SlashCommand を呼ぶ:
     - `/review-implementation`
     - 完了後: review skill が生成した review JSON のパス（`.skills-state/implement/round-N-review.json`）を引数に渡して
       `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/record-review.sh implement <review-json-path>`
     - record-review.sh が次の stage（done / fix / escalate）を決めて state に書き込む
   - `fix`: 次の SlashCommand を呼ぶ:
     - `/fix-implementation`
     - 完了後: `bash ${CLAUDE_SKILL_DIR}/../_common/scripts/advance-state.sh implement review`（iteration が自動でインクリメントされる）
   - `done` / `escalate`: 何もせず終了サマリを表示
4. **ループ**: 上記が 1 stage 終わったら、再度 step 1 から繰り返す。`passed == true` か `escalated == true` になるまで自動で回す。

## 終了時の最終サマリ

最後に必ず次のコマンドを実行して結果を表示する:

```bash
bash ${CLAUDE_SKILL_DIR}/../_common/scripts/summarize-state.sh implement
```

加えて、PASS の場合は「`implement` phase 完了。次フェーズに進めます」、ESCALATE の場合は「上限到達。未解決 BLOCK を人手レビューしてください: <一覧>」と明示する。

## 注意事項

- 必ず冒頭で state を読み、stage に応じて分岐する。**state を無視して何かを書き始めない**。
- sub-skill 呼び出しは **SlashCommand ツール** で行う（Bash で直接 .md を実行しない）。
- review skill が JSON を出さなかった、または不正だった場合は orchestrator を即停止し、ユーザーに報告する。
- fix skill は BLOCK + SUGGEST を対象に修正する。NIT には触らない（review skill 側で対象外）。

- implement phase では produce skill (`/implement-from-issue`) が内部で品質ゲート（UT / 静的解析）を Pattern 2 で並列実行する想定です（E2E は対象外・AWS 環境構築後の別工程）（記事の Pattern 2 Parallel Fan-Out）。
- そのため review-implementation は「コード差分のレビュー」+「品質ゲートが緑であることの確認」を兼ねます。
- fix-implementation は同じ feature ブランチに追加コミットし、既存 PR を更新します（新規 PR は作りません）。

## 参考

- 設計: [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md)
- state JSON スキーマ: 設計ドキュメントの「4. state JSON スキーマ」
- review JSON スキーマ: 設計ドキュメントの「5. review JSON スキーマ」
