---
name: verify-fix
description: 前回レビューの BLOCK/SUGGEST が fix で対応されたかを検証し、結果を JSON で出力する。オーケストレーター（*-loop）から fix 直後に呼ばれる。再実行判断はオーケストレーターの責務。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Write
---

# fix 対応検証（verify-fix）
> **STATE_DIR の解決（D-03・最初に必ず 1 回）**: `STATE_DIR="$(bash .claude/skills/_common/scripts/state-dir.sh <phase>)"` を実行し、以降の `<STATE_DIR>` はこの絶対パスを指す。`.skills-state/...` の相対パス直書きは禁止（書き手による state 置き場の分裂防止）。


> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - implement phase の場合: own リポジトリ（レビュー対象の実装リポ）で実行される。docs 参照は上記ルールに従う。

このスキルはオーケストレーター（`*-loop`）の **fix 直後のゲート** として機能する。

**`context: fork` 必須**: fix skill の思考プロセスを引き継がず、実際のファイル差分だけで独立判定するため。

> **判定の独立性（厳守）**:
> - 本スキルは **前回レビューの各 finding が対応されたか** だけを判定する。新たな品質問題の発見は行わない（それは次の review skill の責務）。
> - 「対応が不完全だが許容範囲」という曖昧な判定をしない。BLOCK は対応済みか未対応かの二値で判定する。

## 役割

前回の review JSON（`round-<N>-review.json`）に記載された BLOCK・SUGGEST の各 finding について、`path`（指摘対象ファイル）と `related_files`（関連ファイル）だけを Read し、fix が実際に対応したかを検証する。

## 入出力

- 入力（引数）: review JSON のパス（オーケストレーターが渡す）
- 入力（ファイル）: 各 finding の `path` と `related_files` に記載されたファイル
- 出力: `<STATE_DIR>/verify-fix-<N>.json`
- 出力（標準出力）: 検証結果の JSON パスを 1 行で出力

## 手順

1. **引数から review JSON のパスを取得**: オーケストレーターから渡された review JSON パスを使う。
2. **review JSON を Read**: findings 配列を取得する。phase と iteration も取得する。
3. **BLOCK と SUGGEST を抽出**: NIT は検証対象外（fix が対応しなくても許容）。
4. **各 finding を検証**: finding ごとに以下を行う:
   - `path` のファイルを Read する（ファイルが存在しない場合は「未対応」）。
   - `related_files` があればそれらも Read する。
   - `message` に記載された指摘内容が解消されているかを判定する。
   - `suggested_fix` があれば、それに沿った修正が行われたかも確認する。
   - 判定結果を `addressed`（対応済み）/ `not_addressed`（未対応）/ `partially_addressed`（部分対応）で記録する。
   - **`path` と `related_files` 以外のファイルは Read しない**（スコープを限定し、不要なファイル読み込みを防ぐ）。
5. **検証結果 JSON を Write**: 後述のスキーマで `<STATE_DIR>/verify-fix-<N>.json` に書き出す。

> **要件フィードバック起票の扱い（D-01）**: design phase の fix が『要件フィードバック起票』（`<STATE_DIR>/requirements-feedback.md` への追記）で対応した finding は、起票内容が指摘に対応していれば addressed と判定してよい（採択済み要件を設計フェーズで直接編集しないための正規経路）。
6. **標準出力に JSON パスを 1 行で出す**。

## 検証の判定基準

- **addressed**: `message` で指摘された問題がファイル上で解消されている（修正・追記・削除等）
- **not_addressed**: `message` で指摘された問題がファイル上にそのまま残っている
- **partially_addressed**: 一部は対応されたが、指摘の核心部分が未解消（BLOCK の場合は `not_addressed` と同等に扱う）

## 出力 JSON スキーマ

```json
{
  "phase": "<requirements | design | implement>",
  "iteration": <int>,
  "verified_at": "<UTC ISO8601>",
  "review_json_path": "<検証元の review JSON パス>",
  "all_blocks_addressed": true | false,
  "summary": {
    "block": { "total": <int>, "addressed": <int>, "not_addressed": <int> },
    "suggest": { "total": <int>, "addressed": <int>, "not_addressed": <int> }
  },
  "results": [
    {
      "severity": "BLOCK | SUGGEST",
      "category": "<category>",
      "path": "<指摘対象ファイル>",
      "original_message": "<元の指摘内容>",
      "status": "addressed | not_addressed | partially_addressed",
      "evidence": "<判定根拠を1〜2文で記載>"
    }
  ]
}
```

## オーケストレーターでの使い方

```
fix 完了後:
  1. /verify-fix <review-json-path> を呼ぶ
  2. verify-fix JSON を Read し、all_blocks_addressed を確認
  3. オーケストレーターが all_blocks_addressed の値に基づいて次のアクションを決定
     （fix 再実行の回数制限・review への遷移判断はオーケストレーターの責務）
```

## 注意事項

- **このスキルでファイルを書き換えない**（diagnostics のみ）。修正は fix skill の責務。
- **新たな品質問題を指摘しない**。未報告の問題を見つけても findings に追加しない（次の review の責務）。
- verify-fix の結果は **review skill に渡さない**（review の判定独立性を保つため）。オーケストレーター層で完結させる。
