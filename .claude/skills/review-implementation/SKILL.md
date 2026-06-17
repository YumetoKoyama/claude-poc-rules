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

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4 における **review** 段を担当します。

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

1. **state を Read**: iteration を取得。
2. **差分の特定**: `git diff --name-only main...HEAD` で変更ファイル一覧を取得。
3. **関連設計書を特定**: state または Issue 本文から SCR-XXX / API 名 / テーブル名を抽出し、`docs/design/` の該当ファイルを Read。
4. **品質ゲート結果の確認**（実行済みかをレポートの更新時刻で判定する。`implement-from-issue` 手順 5 の固定パスより新しいレポートが無ければ category=`quality_gate` の BLOCK とする）:
   - バックエンド: `mvn test` の最新結果、JaCoCo カバレッジレポート、SpotBugs / Checkstyle / PMD レポート
   - フロントエンド: `npm test` の Vitest / Jest 結果、Istanbul カバレッジ、ESLint / TypeScript 型チェック
   - テスト設計マトリクス（単体）: `bash .claude/skills/_common/scripts/check-test-matrix.sh docs/test <ISSUE> unit` を実行し、**存在・構造**（単体マトリクスの TC 行・RTM の Issue 行）を確認する。exit 1 なら category=`quality_gate` の BLOCK（produce 段でゲートが回っていない）。存在が確認できたら、レビューは以降の観点で **単体テストの中身のカバレッジ** を評価する。※**結合テスト（IT-XXX）は本レビューの対象外**（設計・実施とも結合テスト工程＝`/integration-test-from-design` が担い、その工程のレビューで評価する）。
5. **コードレビュー**: 差分ファイルを Read し、設計書と突き合わせる
5.4. **起動配線チェック（必須）**: 差分に「初期化が必要なモジュール」が含まれる場合、起動側の呼び出しが存在するかを確認する。
   ```bash
   # 「呼び出すこと」系のコメントを持つエクスポートを特定
   git diff main...HEAD -- '*.ts' '*.tsx' '*.java' | grep -E '呼び出す|一度だけ|once.*call|init.*inject|注入する' | grep -v '^-'
   ```
   上記で検出された関数・クラスについて、本番起動パス（`app/layout.tsx`・`RootLayout`・`main()` 等）での呼び出しが差分または既存コードに存在するかをGrepで確認する。テストの `beforeEach` だけに呼び出しが存在する場合は category=`wiring` の BLOCK とする。
5.6. **バリデーター型整合チェック（必須）**: 差分に `ConstraintValidator` または Bean Validation アノテーション（`@Valid`・カスタム `@Annotation`）が含まれる場合、バリデーター型パラメーターとフィールド型の整合を確認する。
   ```bash
   # ① 差分に追加・変更された ConstraintValidator 実装を抽出
   git diff main...HEAD -- '*.java' | grep -E "implements ConstraintValidator<" | grep -v '^-'
   # ② 差分に追加・変更されたフィールドのアノテーションを抽出
   git diff main...HEAD -- '*.java' | grep -E "^\+.*@[A-Z][a-zA-Z]+" | grep -v '^-'
   ```
   `ConstraintValidator<Annotation, T>` の `T` が `@Annotation` を付与するフィールドの実際の型（`OffsetDateTime`・`String` 等）と一致するかを確認する。不一致（例: `ConstraintValidator<FutureDatetime, LocalDateTime>` を `OffsetDateTime` フィールドに適用）は Hibernate Validator が実行時に `HV000030: No validator could be found` を投げて 500 エラーになる。コンパイル・静的解析では検出されない。不一致が 1 件でもあれば category=`validator_type` の BLOCK とする。
5.7. **コントローラーテスト MockMvc チェック（推奨）**: 差分に `@Valid @RequestBody` を持つコントローラーメソッドが含まれる場合、対応するテストが `MockMvc.perform()` 経由でリクエストを送信しているかを確認する。
   ```bash
   # ① 差分のコントローラーに @Valid @RequestBody が含まれるか
   git diff main...HEAD -- '*/presentation/*.java' | grep -E "@Valid|@RequestBody" | grep -v '^-'
   # ② 対応するテストクラスに MockMvc 使用箇所があるか
   git diff main...HEAD -- '*Test.java' '*Tests.java' | grep -E "mockMvc|MockMvcRequestBuilders|\.perform\(" | grep -v '^-'
   # ③ コントローラーメソッドを直接呼び出しているテストがあるか
   git diff main...HEAD -- '*Test.java' '*Tests.java' | grep -E "controller\.[a-z][a-zA-Z]+\(" | grep -v '^-'
   ```
   `@Valid @RequestBody` を持つメソッドのテストがコントローラー直呼び出し（`controller.method(req, user)`）のみの場合、Spring MVC の HandlerMethodArgumentResolver が動かないため Bean Validation が一切実行されない。カスタムバリデーターの型不一致など実行時エラーがテストで検出されなくなる。MockMvc テストが 1 件も無い場合は category=`test_design` の SUGGEST として報告する。
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
- `traceability`: Issue の受け入れ条件 **AC-XXX（AC が無い基盤 Issue は設計書「実装内容」項目）に対応する単体テスト（TC-XXX）が 1 件も無い真のカバレッジ穴**（単体マトリクス・RTM を横串で確認して検出）、またはコミットメッセージに Issue 参照（`#N` / `Refs:`）がない。※マトリクス/RTM の **存在・構造**（ファイル有無・TC 行・Issue 行）は produce 段のハードゲート `check-test-matrix.sh ... unit` が担保するため、本観点は **単体カバレッジの中身** を見る。結合テスト（IT）のカバレッジは結合テスト工程のレビューが担当
- `wiring`: アプリ起動配線の欠落。本 Issue で追加・変更したモジュールに「○○から呼び出すこと」「一度だけ呼び出す」「注入する」等の注釈付き初期化関数・Provider・設定関数が含まれる場合、対応する起動側（`layout.tsx`・`Providers`・`main()` 等）での呼び出しが差分に含まれているかを確認する。テストコードの `beforeEach` でのみ初期化されており本番起動パスに呼び出しがない場合は BLOCK
- `validator_type`: `ConstraintValidator<A, T>` の型パラメーター `T` と `@A` アノテーション付与フィールドの実際の型が不一致。Hibernate Validator が実行時に `HV000030: No validator could be found` を投げて 500 エラーになる。コンパイル・静的解析では検出されないため手動確認が必須（手順: ステップ 5.6）
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

review-requirements と同じ。`phase: "implement"`、`category` には上記カテゴリを使う。追加カテゴリ: `wiring`（アプリ起動配線の欠落）、`validator_type`（ConstraintValidator 型不一致）。

## 注意事項

- このスキルではコードを書き換えない（diagnostics のみ）。
- 品質ゲートが**実行されていない**場合は、それ自体を `BLOCK` category=`quality_gate` として報告する。
- 差分が巨大（>30 ファイル）の場合は、サマリで「巨大変更につき抜本見直しを推奨」と明記。
- `message` / `title` / `recommendation` などの自然言語フィールドで語句を強調する場合は、ASCII の `"..."` ではなく **鉤括弧 `「...」`** を使う。JSON 文字列内の `"` エスケープ漏れ事故を減らすため（過去発生事例あり）。
