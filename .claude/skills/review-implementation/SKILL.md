---
name: review-implementation
description: 現在の feature ブランチの実装差分（コード + 品質ゲート結果）をレビューし、BLOCK/SUGGEST/NIT の重大度付き JSON を出力する。implement-loop オーケストレータから呼ばれる。
disable-model-invocation: true
context: fork
allowed-tools: Bash, Read, Glob, Grep, Write
---

# 実装レビュー

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4 における **review** 段を担当します。

**`context: fork` 必須**: produce skill（`/implement-from-issue`）の判断に引きずられず、コード差分と品質ゲート結果だけで独立評価するため。

## 役割

feature ブランチの実装差分・設計書との整合・品質ゲート(UT / 静的解析)の通過状況を観点別にレビューし、機械可読 JSON を生成する。

## 入出力

- 入力: 現在の feature ブランチ（`git diff main...HEAD`）
- 入力: 対応する Issue の設計書（`docs/design/` 配下の関連ファイル）
- 入力: 品質ゲートの実行結果（`build/` `target/` `coverage/` 等のレポート）
- 入力: `.skills-state/implement/state.json`
- 出力: `.skills-state/implement/round-<N>-review.json`
- 出力（標準出力）: 生成した review JSON のパスを 1 行

## 手順

1. **state を Read**: iteration を取得。
2. **差分の特定**: `git diff --name-only main...HEAD` で変更ファイル一覧を取得。
3. **関連設計書を特定**: state または Issue 本文から SCR-XXX / API 名 / テーブル名を抽出し、`docs/design/` の該当ファイルを Read。
4. **品質ゲート結果の確認**（実行済みかをレポートの更新時刻で判定する。`implement-from-issue` 手順 5 の固定パスより新しいレポートが無ければ category=`quality_gate` の BLOCK とする）:
   - バックエンド: `mvn test` の最新結果、JaCoCo カバレッジレポート、SpotBugs / Checkstyle / PMD レポート
   - フロントエンド: `npm test` の Vitest / Jest 結果、Istanbul カバレッジ、ESLint / TypeScript 型チェック
5. **コードレビュー**: 差分ファイルを Read し、設計書と突き合わせる
5.5. 切断チェック（必須）: 差分ファイルを切断・破損の観点で機械的に検出し、得られた findings を自分の review JSON に取り込む。
   ```bash
   FILES=$(git diff --name-only main...HEAD | tr '\n' ' ')
   if [[ -d docs/test ]]; then FILES="$FILES docs/test/"; fi
   if [[ -n "$FILES" ]]; then
     bash .claude/skills/_common/scripts/check-truncation.sh $FILES
   fi
   ```
   - 出力は findings JSON 配列（BLOCK / SUGGEST / NIT の重大度付き）。
   - 検出内容: Invalid UTF-8（マルチバイト文字途中切断 = BLOCK）、日本語末尾で句読点なし（SUGGEST）、Markdown テーブル行が `|` で閉じていない（SUGGEST）、末尾近傍で括弧未閉じ（SUGGEST）、末尾改行なし（NIT）。
   - スクリプトの findings は **自分の手動レビューで作成した findings 配列に merge してから JSON を Write する**。重複（同一 path × 同一 message）は片方だけ残す。コード本体（.java/.ts 等）も UTF-8 不正は検出する。

6. **JSON を Write**

7. **JSON 検証（必須）**: 書き出した JSON を次のコマンドで検証する:
   ```bash
   bash .claude/skills/_common/scripts/validate-review-json.sh <output-path>
   ```
   - パース失敗（exit 1）した場合は stderr のエラー位置と前後コンテキストを Read で確認し、未エスケープの `"` `\` 生改行を修正して再 Write → 再検証する。
   - 最大 3 回まで自己修正を試み、それでも通らない場合は標準出力に `ERROR: invalid JSON after 3 attempts` を出力して停止する（orchestrator が中断する）。
8. **標準出力に JSON パスを 1 行**

## レビュー観点

### BLOCK

- `quality_gate`: 単体テスト・静的解析のいずれかが**失敗**（E2E は品質ゲート対象外。AWS 環境構築後に E2E リポジトリの別工程）
- `coverage`: バックエンドカバレッジ < 80%（CLAUDE.md 基準。これは合格ライン。`/coverage-to-100` は努力目標であり BLOCK 判定は 80% で行う）、または明確な未テストパスがある
- `design_mismatch`: 実装が設計書と矛盾（API パス・メソッド・スキーマの不一致、テーブル定義との不整合）
- `security`: OWASP ベースの脆弱性点検（PR 作成前に必須）。SQL インジェクション・XSS・**認可バイパス / IDOR・テナント越境（自社外リソースへの参照・操作）**・JWT 検証漏れ（署名・失効・有効期限）・PII / 機密情報のログ・レスポンス出力・入力サニタイズ漏れ・ハードコードされたシークレット。`docs/design/セキュリティテスト観点.md` の観点と対応づけ、未対応があれば BLOCK
- `architecture`: Controller に業務ロジック、フロントに業務判定、REST 以外の画面描画、`.env` の直接コミット
- `traceability`: Issue の受け入れ条件 AC-XXX に対応するテストがない、コミットメッセージに Issue 参照（`#N` / `Refs:`）がない
- `git`: `main` / `master` / `develop` への直接 commit、`.github/workflows/**` の編集（deny ポリシー違反）

### SUGGEST

- `readability`: 関数が長すぎる（>50 行）、ネストが深い（>4 段）、命名が説明的でない
- `duplication`: 同じロジックの複数箇所重複（DRY 違反）
- `error_handling`: 例外ハンドリングが粗い（catch して握り潰し、ログだけ）
- `performance`: N+1 クエリ、不要なレンダリング、未使用 import
- `i18n`: ハードコードされた日本語メッセージで国際化未対応（要件で求められている場合）
- `test_design`: 単体テストマトリクス（`docs/test/単体テストマトリクス.md`）・**結合テストマトリクス（`docs/test/結合テストマトリクス.md`・IT-XXX）**・E2E シナリオ表が AC-XXX と対応づいていない、正常系 / 異常系 / 境界値 / 権限境界 の区分が欠けている、またはテストケース ID（TC-XXX / IT-XXX / E2E-XXX）が採番されていない。単体（Service モック）と E2E の中間（実 DB 結合・サービス間結合）が欠落している場合も指摘する
- `traceability_matrix`: `docs/test/トレーサビリティマトリクス.md`（RTM）が無い、または今回の Issue / AC-XXX / テスト ID が RTM に反映されていない（カバレッジ漏れの横串検出ができない）
- `nonfunc_test`: 設計 `docs/design/非機能テスト計画.md` に定義された非機能要求値（性能・負荷・可用性）の検証が、該当する実装変更に対して計画・実施されていない
### NIT

- `style`: フォーマッタが直せる範囲（Prettier / Spotless で吸収可能）
- `typo`: コメント・変数名の軽微な誤字

## 出力 JSON スキーマ

review-requirements と同じ。`phase: "implement"`、`category` には上記カテゴリを使う。

## 注意事項

- このスキルではコードを書き換えない（diagnostics のみ）。
- 品質ゲートが**実行されていない**場合は、それ自体を `BLOCK` category=`quality_gate` として報告する。
- 差分が巨大（>30 ファイル）の場合は、サマリで「巨大変更につき抜本見直しを推奨」と明記。
- `message` / `title` / `recommendation` などの自然言語フィールドで語句を強調する場合は、ASCII の `"..."` ではなく **鉤括弧 `「...」`** を使う。JSON 文字列内の `"` エスケープ漏れ事故を減らすため（過去発生事例あり）。
