---
name: review-implementation
description: 現在の feature ブランチの実装差分（コード + 品質ゲート結果）をレビューし、BLOCK/SUGGEST/NIT の重大度付き JSON を出力する。implement-loop オーケストレータから呼ばれる。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Write
---

# 実装レビュー

> **パス解決（マルチリポジトリ対応）**:
> - **読み取り入力（docs リポジトリ＝claude-poc-docs）**: `docs/requirements/`・`docs/design/` は docs リポジトリ ルート相対。docs をカレントで実行ならそのまま、親アンブレラからなら `claude-poc-docs/` を前置、CI で workflow が追加チェックアウトした docs があればそのパス、無ければ Issue 本文の埋め込み設計を使う。
> - **書き込み出力（own リポジトリ＝レビュー対象の実装リポジトリ）**: レビュー結果 `docs/test/レビュー結果/implement-issue-<ISSUE>.md` は **own リポジトリのワーキングツリー直下** に書き、feature ブランチへ commit/push して **PR に含める**。docs リポジトリ（claude-poc-docs）には書かない（CI では読み取り専用で push されず PR に残らないため）。`.skills-state/` は own リポジトリ直下（gitignore 対象・ephemeral）。

このスキルは Pattern 4（Iterative Loop）における **review** 段を担当します。

**`context: fork` 必須**: produce skill（`/implement-from-issue`）の判断に引きずられず、コード差分と品質ゲート結果だけで独立評価するため。

## 役割

feature ブランチの実装差分・設計書との整合・品質ゲート(UT / 静的解析)の通過状況を観点別にレビューし、機械可読 JSON を生成する。

## 入出力

- 入力: 現在の feature ブランチ（`git diff main...HEAD`）
- 入力: 対応する Issue の設計書（`docs/design/` 配下の関連ファイル）
- 入力: 品質ゲートの実行結果（`build/` `target/` `coverage/` 等のレポート）
- 入力: `.skills-state/implement/state.json`
- 出力: `.skills-state/implement/round-<N>-review.json`（own リポ直下・gitignore）
- 出力: **own リポジトリ**の `docs/test/レビュー結果/implement-issue-<ISSUE>.md`（人間用サマリ。PR 差分に残す正。同一 Issue の round は同ファイルの最上部へ追記。**docs リポには書かない**）。書いた後、feature ブランチへ commit/push して PR に含める
  - **レビュー結果は `docs/test/レビュー結果/` フォルダ配下に、対象がわかるファイル名（`implement-issue-<ISSUE>.md`）で出力する**。Issue ごと・工程ごとにファイルを分けることで、複数 Issue・複数実行での同名衝突と PR 間のマージ競合を防ぐ（旧 `docs/test/レビュー結果.md` 単一ファイルは廃止。過去分は移動しない）
  - `<ISSUE>` は state（`extra_args`）から取得する。取得できない場合は現在のブランチ名 `feature/issue-<N>` から抽出する
- 出力（標準出力）: 生成した review JSON のパスを 1 行

## 手順

1. **iteration を取得（独立化・rules 改善）**: `bash .claude/skills/_common/scripts/get-review-iteration.sh implement` を実行し、stdout の数値を `N` とする。出力ファイル名を `round-<N>-review.json` とする。**state.json を直接 Read してはならない**（判定の独立性のため）。`<ISSUE>` は state（`extra_args`）またはブランチ名 `feature/issue-<N>` から取得する。
2. **差分の特定**: `git diff --name-only main...HEAD` で変更ファイル一覧を取得。
3. **関連設計書を特定**: state または Issue 本文から SCR-XXX / API 名 / テーブル名を抽出し、`docs/design/` の該当ファイルを Read。**あわせて横断設計書 `docs/design/共通部品設計.md`・`docs/design/フロントエンド共通設計.md` を必ず Read し、定義済み共通部品（共通 API クライアント `apiClient.ts` / 共通エラーハンドリング / 共通バリデーション / 共通レイアウト / `JwtUtil` 等）の一覧を把握する（`common_component` 観点の照合先・rules 改善）。さらに `.claude/rules/frontend-*.md`（特に `frontend-routing.md` の認可制御3層・`frontend-99-contract-auth-deps.md`・`frontend-state-api.md`・`frontend-directory-structure.md`・`frontend-coding-rules.md`）を Read し、FE 確定規約を把握する（`frontend_convention` 観点の照合先。正典は frontend ルール）。**
4. **品質ゲート結果の確認（内容依存判定・rules 改善 RC-07・収束不能バグ修正）**: レポートの **更新時刻にもコミットハッシュにも依存しない**。代わりに `bash .claude/skills/_common/scripts/gate-content-hash.sh` を **再計算** し、`implement-from-issue` / `fix-implementation` がゲート実行直後に保存した `coverage/.gate-content`（コード内容ハッシュ）と照合して、**現在のコードに対して実際に実行されたレポートか**を判定する。一致すれば有効。`docs(review)` 等のコードを変えないコミットではハッシュが変化しないため、旧 `.gate-commit==HEAD` 方式で起きていた誤検知（HEAD が進むたびに `quality_gate` が立ち、ループが収束しない）は発生しない。
   - 判定: ①レポートが**存在しない** → category=`quality_gate` の **BLOCK**（理由「レポート不在」を別 finding として明記）。②サイドカー（`coverage/.gate-content`）が存在し**再計算したコード内容ハッシュと一致しない** → category=`quality_gate` の **BLOCK**（理由「古いコードに対するレポート（内容不一致）」）。③ハッシュ一致＝現コードに対して実行済み → ゲート通過の前提で中身の評価に進む。
   - **移行期フォールバック**: `.gate-content` が存在しない旧形式レポートに限り、従来の `.gate-commit`（現 HEAD 照合）／レポート更新時刻でフォールバック判定してよい。いずれでも実行が確認できなければ category=`quality_gate` の BLOCK とする（サイドカー配備後は時刻・コミットハッシュ依存を廃止する前提）。
   - フロントエンド: `npm test` の Vitest / Jest 結果、Istanbul カバレッジ（`coverage/`）、ESLint（`eslint-report.json`）/ TypeScript 型チェック
   - **カバレッジ閾値の機械判定（rules 改善）**: `bash .claude/skills/_common/scripts/check-coverage-threshold.sh frontend` を実行し、exit 1 は category=`coverage` の BLOCK とする（**ファイル/パッケージ単位で未達箇所を列挙**して finding 化する。「全体未達」だけで済ませない）。
   - テスト設計マトリクス（単体）: `bash .claude/skills/_common/scripts/check-test-matrix.sh docs/test <ISSUE> unit` を実行し、**存在・構造**（単体マトリクスの TC 行・RTM の Issue 行）を確認する。exit 1 なら category=`quality_gate` の BLOCK（produce 段でゲートが回っていない）。存在が確認できたら、レビューは以降の観点で **単体テストの中身のカバレッジ** を評価する。※**結合テスト（IT-XXX）は本レビューの対象外**（設計・実施とも結合テスト工程＝`/integration-test-from-design` が担い、その工程のレビューで評価する）。
5. **コードレビュー**: 差分ファイルを Read し、設計書と突き合わせる
5.5. 切断チェック（必須）: 差分ファイルを切断・破損の観点で機械的に検出し、findings JSON を一時ファイルに保存する。
   ```bash
   FILES=$(git diff --name-only main...HEAD | tr '\n' ' ')
   if [[ -d docs/test ]]; then FILES="$FILES docs/test/"; fi
   if [[ -n "$FILES" ]]; then
     bash .claude/skills/_common/scripts/check-truncation.sh $FILES
   fi
   ```
   - 出力は findings JSON 配列（BLOCK / SUGGEST / NIT の重大度付き）。
   - 検出内容: Invalid UTF-8（マルチバイト文字途中切断 = BLOCK）、日本語末尾で句読点なし（SUGGEST）、Markdown テーブル行が `|` で閉じていない（SUGGEST）、末尾近傍で括弧未閉じ（SUGGEST）、末尾改行なし（NIT）。
   - スクリプトの findings JSON は `.skills-state/implement/round-<N>-check-truncation.json` 等の一時ファイルに保存し、`format-review-json.sh` の `--merge-json` で取り込む（手動マージ禁止）。重複（同一 path × 同一 message）は自動的に片方だけ残る。コード本体（.java/.ts 等）も UTF-8 不正は検出する。

6. **findings を TSV で出力（JSON 手書き禁止・P-08）**: 自分のレビューで見つけた指摘を
   `.skills-state/implement/round-<N>-findings.tsv` に 1 行 1 指摘のタブ区切りで Write する
   （列: severity/category/path/line/message/suggested_fix/related_files。message 内の強調は鉤括弧「」を使い、タブ・改行を含めない）。
   決定論スクリプト（check-*.sh）の findings JSON はファイルに保存しておき、手動でマージしない。
7. **検査済み観点リストを TSV で出力（P-10・必須）**: `.skills-state/implement/round-<N>-aspects.tsv` に、
   本スキルの全レビュー観点カテゴリ + 実行した決定論スクリプトを 1 行ずつ
   （列: aspect/status(checked|partial|not-checked)/method(script|llm|none)/note）記載する。
   全観点を必ず列挙し、見なかった観点は not-checked + 理由を書く（沈黙スキップの禁止）。
7.5. **review JSON を機械生成**:
   ```bash
   bash .claude/skills/_common/scripts/format-review-json.sh implement \
     .skills-state/implement/round-<N>-findings.tsv \
     .skills-state/implement/round-<N>-review.json \
     --aspects .skills-state/implement/round-<N>-aspects.tsv \
     --summary <summaryファイル(任意)> \
     --merge-json <check-*.shのfindings JSONファイル>...
   ```
   生成とスキーマ検証は機械化されているため、JSON の自己修正リトライは不要。TSV 形式エラー（exit 1）の場合のみ該当行を直して再実行する。
8. **レビュー結果サマリ（人間用）を own リポジトリへ Write（必須・標準出力の直前に実施）**: **own リポジトリ**の `docs/test/レビュー結果/implement-issue-<ISSUE>.md`（＝レビュー対象の実装リポのワーキングツリー直下。`claude-poc-docs/` を前置しない）に、人間がレビューできる Markdown サマリを出力する。`.skills-state` の JSON は gitignore 対象で消えるため、**PR 差分に残るこのファイルが人間向けの正となる**。
   - フォルダが無ければ作成する（`mkdir -p docs/test/レビュー結果`）。
   - 同一 Issue の既存ファイル（`docs/test/レビュー結果/implement-issue-<ISSUE>.md`）があれば Read し、**今回の round セクションを最上部に追記**（過去 round は残す。最新が一番上）。**他の Issue のファイルには触れない**。
   - フォーマット:
     ```markdown
     # レビュー結果（implement / Issue #<ISSUE> <Issue タイトル>）

     > 最新 round が最上部。各 round は機械可読 JSON（`.skills-state/.../round-<N>-review.json`）を人間向けに整形したもの。

     ## Round <N> — <YYYY-MM-DD HH:MM> — overall: <PASS|FAIL>（BLOCK <件> / SUGGEST <件> / NIT <件>）

     | 重大度 | カテゴリ | 該当 | 指摘 | 推奨対応 | 対応状況 |
     |---|---|---|---|---|---|
     | BLOCK | <category> | <path:line> | <message> | <suggested_fix> | 未対応 |
     | SUGGEST | ... | ... | ... | ... | 未対応 |
     ```
   - findings は **BLOCK → SUGGEST → NIT** の順に並べる。JSON の findings と件数・内容を一致させる。
   - 「対応状況」列は初期値 `未対応`。後続の fix skill が反映したら `対応済み` / `見送り（理由）` に更新する想定（fix skill 側で更新）。
   - BLOCK が 0 件で overall=PASS の場合も、その round セクション（指摘なし）を必ず残し、採択者が「クリーンで PASS した」ことを確認できるようにする。
8.5. **レビュー結果を PR に反映（commit/push）**: `docs/test/レビュー結果/implement-issue-<ISSUE>.md` のみを現在の feature ブランチへ commit/push し、PR に含める（コード本体には触れない＝diagnostics のみの原則は維持。コミット対象はこのレビュー成果物だけ）。
   ```bash
   git add "docs/test/レビュー結果/implement-issue-<ISSUE>.md"
   git commit -m "docs(review): implement round <N> レビュー結果 (#<ISSUE>)" || true
   git push || true
   ```
9. **標準出力に JSON パスを 1 行**

## レビュー観点

### BLOCK

- `quality_gate`: 単体テスト・静的解析のいずれかが**失敗**（E2E は品質ゲート対象外。AWS 環境構築後に E2E リポジトリの別工程）
- `coverage`: バックエンドカバレッジが確定表 #13 の閾値（命令(INSTRUCTION)100% / 分岐(BRANCH)90%、いずれも除外後）を下回る（＝`mvn verify` の jacoco:check が落ちる水準）、フロントエンドが確定表 #10（100%、除外後）を下回る、または明確な未テストパスがある。閾値の正典は各確定表（`backend-00-stack.md` #13 / `frontend-00-stack.md` #10）であり、CLAUDE.md は閾値を持たない。`/coverage-to-100` は不足時の改善手順（旧「80%」基準は廃止）
- `design_mismatch`: 実装が設計書と矛盾（API パス・メソッド・スキーマの不一致、テーブル定義との不整合）
- `security`: OWASP ベースの脆弱性点検（PR 作成前に必須）。SQL インジェクション・XSS・**認可バイパス / IDOR・テナント越境（自社外リソースへの参照・操作）**・JWT 検証漏れ（署名・失効・有効期限）・PII / 機密情報のログ・レスポンス出力・入力サニタイズ漏れ・ハードコードされたシークレット。`docs/design/セキュリティテスト観点.md` の観点と対応づけ、未対応があれば BLOCK
- `architecture`: Controller に業務ロジック、フロントに業務判定、REST 以外の画面描画、`.env` の直接コミット
<!-- rules 改善（A-2）: 設計済み共通部品の再発明を BLOCK -->
- `common_component`: 設計済みの共通部品（`docs/design/共通部品設計.md`・`フロントエンド共通設計.md` に定義された共通 API クライアント `apiClient.ts` / 共通エラーハンドリング / 共通バリデーション / 共通レイアウト / `JwtUtil` 等）を**再実装・再発明**している（A-2）。実装差分に共通部品と同責務のコード（`fetch`/`axios` の素呼び出しによる独自 API クライアント、独自の共通エラー整形・トークン管理等）が新規追加され、既存の共通部品を import・利用していない場合は BLOCK。共通設計の部品名を Grep で実装差分と突合し、「設計に存在するのに使われず再発明された」ものを finding 化する。`duplication`(SUGGEST) より重く扱う
<!-- rules 改善: FE 確定規約違反（正典は frontend ルール） -->
- `frontend_convention`: `.claude/rules/frontend-*.md` の確定規約（ディレクトリ構成・状態管理・API 連携・ルーティング認可制御3層・テスト命名）に違反している。正典は frontend ルールであり、違反は BLOCK
- `traceability`: Issue の受け入れ条件 **AC-XXX（AC が無い基盤 Issue は設計書「実装内容」項目）に対応する単体テスト（TC-XXX）が 1 件も無い真のカバレッジ穴**（単体マトリクス・RTM を横串で確認して検出）、またはコミットメッセージに Issue 参照（`#N` / `Refs:`）がない。※マトリクス/RTM の **存在・構造**（ファイル有無・TC 行・Issue 行）は produce 段のハードゲート `check-test-matrix.sh ... unit` が担保するため、本観点は **単体カバレッジの中身** を見る。結合テスト（IT）のカバレッジは結合テスト工程のレビューが担当
- `git`: `main` / `master` / `develop` への直接 commit、`.github/workflows/**` の編集（deny ポリシー違反）

### SUGGEST

- `readability`: 関数が長すぎる（>50 行）、ネストが深い（>4 段）、命名が説明的でない
- `duplication`: 同じロジックの複数箇所重複（DRY 違反）
- `error_handling`: 例外ハンドリングが粗い（catch して握り潰し、ログだけ）
- `performance`: N+1 クエリ、不要なレンダリング、未使用 import
- `i18n`: ハードコードされた日本語メッセージで国際化未対応（要件で求められている場合）
- `test_design`: 単体マトリクスは **存在する前提**（存在・構造はゲートが担保）で **中身の質** を見る。AC（または実装内容項目）↔ TC-XXX の対応が意味的に妥当でない、正常系 / 異常系 / 境界値 / 権限境界 の **区分網羅が不足**、テスト対象（Service / Validation / 例外）の観点が薄い。※AC に対応する単体テストが **皆無** の場合は SUGGEST ではなく BLOCK（`traceability`）。**結合テスト（IT）の設計品質は本レビューの対象外**（結合テスト工程で評価）
- `traceability_matrix`: RTM は **存在し当該 Issue 行がある前提**（存在・Issue 行はゲートが担保）で、**単体の横串カバレッジ漏れ** を見る。RTM 上で UC / AC / SCR に対し TC-XXX の対応が部分的 等。※RTM の横串で単体テストの無い AC を発見した場合は BLOCK（`traceability`）。IT-XXX / E2E-XXX 列の整備は各別工程が担当し、本レビューでは未記入でも指摘しない
- `nonfunc_test`: 設計 `docs/design/非機能テスト計画.md` に定義された非機能要求値（性能・負荷・可用性）の検証が、該当する実装変更に対して計画・実施されていない
### NIT

- `style`: フォーマッタが直せる範囲（Prettier / Spotless で吸収可能）
- `typo`: コメント・変数名の軽微な誤字

## 出力 JSON スキーマ

review-requirements と同じ。`phase: "implement"`、`category` には上記カテゴリを使う。

`checked_aspects` / `uncovered_areas`（P-10）: `format-review-json.sh` が aspects TSV から生成するフィールド。`checked_aspects` は検査した観点の一覧（aspect/status/method/note）、`uncovered_areas` は status が `checked` 以外だった観点（未検査・部分検査とその理由）の一覧。**PASS はこのリストが揃って初めて解釈可能** であり、findings が 0 件でも `uncovered_areas` に重要観点が残っていれば「検査していないだけ」の可能性がある。採択者は `uncovered_areas` を見て残リスクを判断する。

## 注意事項

- このスキルではコードを書き換えない（diagnostics のみ）。
- 品質ゲートが**実行されていない**場合は、それ自体を `BLOCK` category=`quality_gate` として報告する。
- 差分が巨大（>30 ファイル）の場合は、サマリで「巨大変更につき抜本見直しを推奨」と明記。
- `message` / `title` / `recommendation` などの自然言語フィールドで語句を強調する場合は、ASCII の `"..."` ではなく **鉤括弧 `「...」`** を使う。JSON 文字列内の `"` エスケープ漏れ事故を減らすため（過去発生事例あり）。
