---
name: review-implementation-overall
description: 製造工程完了後の成果物全体を横断レビューする。対象は実装リポジトリ群（backend / frontend / batch）の全量（src 配下すべて）で、Issue 単位の review-implementation では見えない「設計書との全体整合」「Issue 横断の不整合」「セキュリティ横断」「RTM/テスト網羅の横串」「リポジトリ間（FE⇔BE）の整合」を点検し、BLOCK/SUGGEST/NIT の重大度付き JSON と人間用 Markdown サマリを出力する。全体レビュー・横断レビューを求められた時に使う。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Write
argument-hint: [対象: backend|frontend|batch|all（既定 all）] [フィーチャ名] [--branch <ブランチ名>]
---

# 実装全体レビュー（横断レビュー）

> **位置づけ**: 製造（`/implement-loop`、Issue 単位の実装＋レビュー）の後段に置く**独立工程**。Issue 単位のレビューは差分（`git diff main...HEAD`）しか見ないため、構成 Issue が `main` に組み上がった後でないと検出できない横断的な不整合を本工程で点検する（結合テスト工程 `/integration-test-from-design` を製造から分離しているのと同じ理由）。**親アンブレラから実行する**（複数実装リポジトリをまたぐため）。
>
> **review のみ（fix なし・ループなし）**: 横断指摘は複数モジュール・複数 Issue・複数リポジトリに波及するため自動修正しない。指摘の採否・修正方法は人手が判断し、必要なら人手で修正 Issue を起票して既存の `/implement-loop` で対応する（採択ゲート思想と整合。Claude・skill が自ら Issue 起票・`@claude` コメントをしてはならない）。
>
> **全量レビュー（省略禁止）**: スコープ内の実装リポジトリは **src 配下の全ファイルを Read する**。時間がかかってもサンプリングで省略しない。レビューしたファイル数・行数をサマリのカバレッジ欄に記録し、全量であることを人間が検証できるようにする。
>
> **review-implementation とは独立した別工程（流用禁止）**: `.skills-state/implement/` の state.json・round 管理・feature ブランチ・`extra_args` の Issue 番号は**一切参照・使用しない**。製造は CI（implement-loop）で完了済みであり、対象コードは Issue ごとに品質ゲート（UT 実行・カバレッジ閾値・静的解析・マトリクスゲート）と PR レビューを通過して `main` にマージされている**前提**で扱う。したがって次の指摘は**禁止**（見当はずれになる）: 「品質ゲートが実行されていない」「カバレッジレポート・ビルドレポートが無い」「feature ブランチ・PR・Issue 参照が無い」等の、Issue 単位の製造プロセスに対する指摘。本工程が見るのは**組み上がった成果物の中身の横断整合のみ**。
>
> **対象の取り違え禁止（フェイルファスト）**: レビュー対象は **git 管理下の実装リポジトリ（`claude-poc-backend/` 等）の対象ブランチのみ**。git 未追跡の一括生成物・実験ディレクトリ（例: `fable-imp/`、`workspace/` 配下の生成物）は、引数で明示指定されない限り**対象にしない**。期待する入力（実装リポ・設計書・マトリクス）が見つからない場合、**別のディレクトリを推測してレビューを続行してはならない**。確認した絶対パスの一覧を提示して中断し、人間に対象を確認する。

> **パス解決（マルチリポジトリ対応・親アンブレラ実行）**:
> - **読み取り入力（docs リポジトリ＝claude-poc-docs）**: 設計書・要件は `claude-poc-docs/docs/design/`・`claude-poc-docs/docs/requirements/`（docs をカレントで実行する場合は前置不要）。
> - **レビュー対象（実装リポジトリ群）**: `claude-poc-backend/`・`claude-poc-frontend/`・`claude-poc-batch/`。各リポの `main`（または `--branch` 指定ブランチ）のワーキングツリー全量。
> - **書き込み出力**: リポごとのレビュー結果 md は **各実装リポジトリ**の `docs/test/レビュー結果/overall-<スコープ>-<YYYYMMDD>.md`。リポ間整合（観点 E）の指摘は関係する**両方のリポ**のサマリに記載する（path にリポ名を前置して区別）。機械可読 JSON は親アンブレラ直下の `.skills-state/overall-review/`（gitignore 対象・ephemeral）に 1 実行 1 ファイル。

対象: $ARGUMENTS

## 入出力

- 入力: スコープ内の各実装リポジトリの対象ブランチ全体（差分ではなくワーキングツリー全量）
- 入力: docs リポジトリの採択済み設計書一式（`docs/design/`）・要件（`権限マトリクス.md`・`コード値定義.md`・`メッセージ一覧.md` 等）
- 入力: 各実装リポジトリの正典ルール（`claude-poc-frontend/.claude/rules/frontend-*.md`・`claude-poc-backend/.claude/rules/backend-*.md`。矛盾時は frontend ルールが正）
- 入力: 各実装リポジトリの `docs/test/単体テストマトリクス.md`・`docs/test/トレーサビリティマトリクス.md`（RTM）・`docs/test/レビュー結果/implement-issue-*.md`（既往指摘）
- 出力: `.skills-state/overall-review/<YYYYMMDD-HHMM>-review.json`（親アンブレラ直下・gitignore。全リポの findings を 1 ファイルに集約、各 finding の `path` はリポ名前置）
- 出力: 各実装リポジトリの `docs/test/レビュー結果/overall-<スコープ>-<YYYYMMDD>.md`（人間用サマリ。`<スコープ>` は `all` / リポ名 / フィーチャ名）
- 出力（標準出力）: 生成した review JSON のパスを 1 行

## 手順

### 1. スコープの確定

1. **実行位置と対象の機械的確定**: まずカレントディレクトリを判定する。
   - 親アンブレラ（`claude-poc-backend/` 等のサブディレクトリが在る）なら各リポにリポ名を前置。
   - 実装リポ直下（`pom.xml` / `package.json` と `src/` が在り、`git rev-parse --is-inside-work-tree` が true）なら対象はそのリポ単体、パスはリポ相対、docs リポは `../claude-poc-docs/`。
   - 対象は **git 管理下のリポジトリのみ**。`git -C <対象> rev-parse --is-inside-work-tree` で確認し、確認結果（絶対パス・ブランチ・HEAD）をサマリに記録する。判定できない場合は**中断**して人間に確認する（推測で別ディレクトリを対象にしない）。
2. 引数を解釈する。第 1 引数で対象リポを決める（`backend` / `frontend` / `batch` / `all`、省略時 `all`）。存在しないリポ（例: batch 未着手）はスキップし、その旨をサマリに明記する。
3. **入力の存在確認（指摘より先に実施）**: 以下を `ls` で機械的に確認し、見つかった絶対パスをサマリの「入力確認」欄に記録する。
   - 各対象リポの `docs/test/単体テストマトリクス.md`・`docs/test/トレーサビリティマトリクス.md`
   - docs リポの `docs/design/`（api/・tables/・screens/）
   - **実在するファイルを「存在しない」と指摘することを禁止する**。「無い」系の指摘を出す場合は、確認に使った絶対パスを `message` に必ず含める。
4. フィーチャ名が指定された場合は、設計書（`docs/design/sequences/*.md`・`screens/*.md`・`api/*.yaml`）から当該フィーチャに属する SEQ-XXX / SCR-XXX / operationId / テーブル / 関連 Issue 群を洗い出し、対象を絞る。省略時はリポジトリ全体。
5. 各対象リポのブランチを確認する（既定 `main`。`--branch` で上書き可）。`git -C <リポ> status` / `git -C <リポ> log -1` で確認し、ログに残す。
6. 入力ドキュメントが docs の `main` にマージ済み（採択済み）であることを確認する（`git -C claude-poc-docs log origin/main -- docs/design/` 等）。未マージなら中断して人手レビュー・マージを依頼する。

### 2. インベントリ作成（突合の土台）

設計と実装の対応表を機械的に作る。レビューの根拠として md サマリに含める。

- **API（BE）**: `docs/design/api/*.yaml` の全 operationId × HTTP メソッド × パス ⇔ backend Controller のエンドポイント実装
- **API（FE）**: 同 operationId ⇔ frontend の API クライアント（呼び出し箇所・リクエスト/レスポンス型）
- **DB**: `docs/design/tables/*.md` の全テーブル ⇔ Entity / Repository / migration
- **画面**: `docs/design/screens/SCR-*.md` の全画面 ⇔ frontend のルーティング・画面コンポーネント
- **バッチ**: `docs/design/バッチ設計.md`・`IF定義.md` の全バッチ/IF ⇔ batch のジョブ実装
- **認可**: `docs/design/認可設計.md`（または `セキュリティ設計.md` 内）の operationId × 必要ロール × テナント条件 ⇔ BE の `@PreAuthorize` 等 ⇔ FE のルートガード・ロール別表示制御
- **テスト**: 各リポの RTM の UC / AC / BR / SCR / API operationId / Issue# / TC-XXX 列 ⇔ 実テストコード

### 3. 横断レビュー（5 観点）

#### 観点 A: 設計書との全体整合（design_coverage / design_mismatch）

- 設計に在って実装に無い: 未実装の operationId・テーブル・画面・バッチ（**実装漏れ = BLOCK**）
- 実装に在って設計に無い: 設計外のエンドポイント・テーブル・カラム・画面・ジョブ（**設計逸脱 = BLOCK**）
- スキーマ不一致: リクエスト/レスポンス型・enum（`_common.yaml` ⇔ `docs/requirements/コード値定義.md` ⇔ 実装定数）・ErrorResponse 形式・MSG-XXX 文言の食い違い
- 画面: `screens/SCR-*.md` の項目・バリデーション・遷移（`画面遷移.md`）⇔ FE 実装の突合

#### 観点 B: Issue 横断の整合性（cross_issue_consistency / duplication / architecture / type_consistency）

個別 Issue のレビューでは「その Issue 内では正しい」が、組み上がると不揃いになるものを見る。各リポの `.claude/rules/` を規約の正典として突合する。

- 同種処理の実装パターンの不統一（例外ハンドリング・レスポンス整形・バリデーション・ページング・日時/タイムゾーン扱い・トランザクション境界・FE の状態管理/データ取得パターンが Issue により異なる）
- 共通部品（`docs/design/共通部品設計.md`・FE 共通コンポーネント）を使うべき箇所での重複実装・独自実装
- 命名・パッケージ/ディレクトリ構成のばらつき
- レイヤー責務違反の横断的な傾向（Controller への業務ロジック漏れ、FE への業務判定・データ整形の漏れ＝Service 側に寄せる方針との乖離）
- **コード構造・型の整合（type_consistency）**: コンパイルは通るが設計として不整合なものを見る（ビルドが通るレベルの型整合は CI 担保のため対象外）
  - 同一概念の型・enum・定数の二重定義（例: ステータス enum が複数パッケージに別定義、FE での文字列リテラル直書き）
  - Entity⇔DTO⇔OpenAPI スキーマのマッピング整合: フィールドの欠落・型のずれ・nullable/必須の食い違い・変換ロジック（Mapper）の片寄り
  - 共通型の不統一: ID（String/Long 混在）・日時（LocalDateTime/Instant/タイムゾーン）・金額（BigDecimal/int）・ページング型などが Issue により異なる
  - 循環依存（パッケージ間・モジュール間）、デッドコード（どこからも参照されないクラス・メソッド・エンドポイント。設計逸脱の残骸の可能性として観点 A と突合）
- **アプリ起動配線（startup_wiring）**: 「○○から呼び出すこと」「一度だけ呼び出す」「注入する」等の注釈付き初期化関数・Provider・設定関数が、実際の本番起動パス（フロントなら `app/layout.tsx` 等、バックエンドなら `main()` や起動 Bean 等）で呼ばれているかを全量確認する。テストコードの `beforeEach` でのみ初期化されており本番起動パスに呼び出しがない場合は **BLOCK**（`startup_wiring`）として報告する。チェック手順:
  ```bash
  # 1. 「呼び出しが必要」系の注釈を持つエクスポートを全量抽出
  grep -rn "呼び出す\|一度だけ\|once.*call\|init.*inject\|注入する" \
    --include="*.ts" --include="*.tsx" --include="*.java" \
    <対象リポ>/src/ | grep -v "__tests__\|\.test\.\|\.spec\.\|/test/"
  # 2. 抽出された関数名を本番起動パスで grep して呼び出し有無を確認
  grep -rn "<関数名>" <対象リポ>/src/ | grep -v "__tests__\|\.test\.\|\.spec\.\|/test/"
  ```
- **バリデーター型整合（validator_type_compatibility）**: カスタム `ConstraintValidator<A, T>` の型パラメーター `T` が、`@A` アノテーションを付与するフィールドの実際の型と一致するかを全量確認する。不一致は Hibernate Validator が実行時に `HV000030: No validator could be found` を投げて 500 エラーになる（コンパイル・静的解析では検出されない）。チェック手順:
  ```bash
  # BE: ConstraintValidator 実装を全量抽出し、アノテーション名を特定
  grep -rn "implements ConstraintValidator<" <リポ>/src/main --include="*.java"
  # 特定したアノテーション名でフィールド付与箇所を検索し型を確認
  grep -rn "@<アノテーション名>" <リポ>/src/main --include="*.java" -A1
  ```
  型不一致が 1 件でもあれば **BLOCK**（`validator_type_compatibility`）。
- **コントローラーテスト MockMvc 確認（controller_test_style）**: `@Valid @RequestBody` を持つコントローラーメソッドのテストが `MockMvc.perform()` 経由でリクエストを送信しているかを全量確認する。コントローラーを直接呼び出す（`controller.method(req, user)` 形式）テストのみの場合、Bean Validation（`@Valid`）がテスト時に実行されず、カスタムバリデーターの型不一致・制約違反が検出されない。チェック手順:
  ```bash
  # @Valid @RequestBody を持つメソッドを特定
  grep -rn "@Valid\|@RequestBody" <リポ>/src/main --include="*.java" -l
  # 対応するテストクラスで MockMvc が使われているか確認
  grep -rn "mockMvc\.perform\|MockMvcRequestBuilders" <リポ>/src/test --include="*.java"
  ```
  MockMvc テストが 1 件も無いコントローラーがあれば **SUGGEST**（`controller_test_style`）。

#### 観点 C: セキュリティ横断（security / authorization）

- 認可設計 × 実装の**全 API 突合**: BE の `@PreAuthorize` 漏れ・ロール不一致（**1 件でも BLOCK**）。FE のルートガード・ロール別表示制御の漏れ（FE は UX 層であり防御の正は BE、ただし要件 `権限マトリクス.md` との不整合は指摘）
- テナント越境: テナントフィルタの適用漏れ箇所の網羅点検、IDOR（ID 直指定での他テナント資源参照）
- JWT 検証（署名・失効・有効期限）の一貫性、FE のトークン保管方式（`セキュリティ設計.md` との突合）、CORS 設定の整合
- XSS（FE: `dangerouslySetInnerHTML` 等の生 HTML 挿入）、機微情報のログ・レスポンス・FE バンドルへの漏えい、ハードコードされたシークレット
- `docs/design/セキュリティテスト観点.md` の各観点に対する実装・テストの対応状況

#### 観点 D: RTM/テスト網羅の横串（traceability / rtm_gap）

- 各リポの RTM を正典として UC / AC / BR / SCR / operationId → TC-XXX の対応を全行点検し、**単体テストが 1 件も無い AC（真のカバレッジ穴）は BLOCK**
- RTM に行が無い実装済み Issue・operationId・画面（RTM の記載漏れ）
- マトリクス上の TC-XXX と実テストコードの乖離（採番だけあって実体が無い等）
- 区分（正常系 / 異常系 / 境界値 / 権限境界）の網羅が薄い領域の指摘
- ※ IT-XXX / E2E-XXX 列の未整備は**指摘しない**（結合テスト工程・E2E 工程の責務）

#### 観点 E: リポジトリ間整合（cross_repo_consistency）※対象が 2 リポ以上の場合

OpenAPI（`docs/design/api/*.yaml`）を境界の正典として FE⇔BE⇔batch を突合する。

- FE の API クライアントの型・パス・メソッド ⇔ BE の実装の不一致（設計を経由しない「実装同士の暗黙の合意」は設計逸脱として BLOCK）
- enum・コード値・MSG-XXX 文言の FE/BE での二重定義・食い違い
- 認可のずれ: BE が拒否するロールの操作が FE で表示・実行可能（またはその逆）
- batch ⇔ BE の共有テーブル・トランザクション境界・排他制御の整合

### 4. 機械チェック（必須）

スコープ内の各リポで実行し、findings を merge する（同一 path × 同一 message の重複は片方だけ残す）。

```bash
bash .claude/skills/_common/scripts/check-truncation.sh <リポ>/docs/test/ <リポ>/src/
bash .claude/skills/_common/scripts/check-test-matrix.sh <リポ>/docs/test <Issue> unit   # スコープ内 Issue ごとに構造確認
```

※ `check-test-matrix.sh` の exit 1 は「マトリクスの構造欠落（当該 Issue 行の不在等）」として category=`quality_gate` で報告する。**「CI の品質ゲートが未実行/未通過」と断定しない**（実行有無は CI が担保済みで本工程の対象外）。

### 5. JSON を Write → 検証

```bash
bash .claude/skills/_common/scripts/validate-review-json.sh .skills-state/overall-review/<YYYYMMDD-HHMM>-review.json
```

パース失敗時は最大 3 回自己修正し、それでも通らなければ標準出力に `ERROR: invalid JSON after 3 attempts` を出して停止する。

### 6. レビュー結果サマリ（人間用）を Write

スコープ内の**各実装リポジトリ**の `docs/test/レビュー結果/overall-<スコープ>-<YYYYMMDD>.md` に出力する（そのリポに関係する findings + 観点 E の関係分）。同日同スコープの既存ファイルがあれば Read し、今回の実行セクションを最上部に追記する。

```markdown
# 全体レビュー結果（overall / スコープ: <all|リポ名|フィーチャ名> / ブランチ: <branch>）

> 最新実行が最上部。機械可読 JSON（親アンブレラ `.skills-state/overall-review/...`）を人間向けに整形したもの。

## <YYYY-MM-DD HH:MM> — overall: <PASS|FAIL>（BLOCK <件> / SUGGEST <件> / NIT <件>）

### 入力確認（対象・前提の証跡）

| 確認項目 | 結果 |
|---|---|
| 対象リポ（絶対パス / ブランチ / HEAD） | <値> |
| 単体テストマトリクス | <絶対パス / 確認済> |
| RTM | <絶対パス / 確認済> |
| 設計書（api/ tables/ screens/） | <絶対パス / 確認済> |

### レビューカバレッジ（全量保証）

| リポ | 対象ファイル数（src） | Read 済み | 省略 |
|---|---|---|---|
| claude-poc-backend | <件> | <件> | なし |

### 突合インベントリ（根拠）

| 突合対象 | 設計 | 実装 | 一致 |
|---|---|---|---|
| API operationId（BE 実装） | <件> | <件> | <OK/差分あり> |
| API operationId（FE クライアント） | <件> | <件> | <OK/差分あり> |
| テーブル | <件> | <件> | <OK/差分あり> |
| 画面 SCR-XXX（FE ルート） | <件> | <件> | <OK/差分あり> |
| 認可（@PreAuthorize） | <件> | <件> | <OK/差分あり> |
| RTM 行（AC→TC） | <件> | <件> | <OK/穴あり> |

### 指摘一覧

| 重大度 | カテゴリ | 該当 | 指摘 | 推奨対応 | 対応状況 |
|---|---|---|---|---|---|
| BLOCK | <category> | <リポ名/path:line> | <message> | <suggested_fix> | 未対応 |
```

- findings は **BLOCK → SUGGEST → NIT** の順。JSON と件数・内容を一致させる。
- BLOCK 0 件で PASS の場合もセクションを必ず残す（「クリーンで PASS した」ことを人間が確認できるように）。

### 7. レビュー結果の反映（PR 経由・main 直 push 禁止）

各リポでレビュー結果 md のみを `docs/review-overall-<YYYYMMDD>` ブランチに commit/push し、PR を作成する（コード本体には触れない＝diagnostics のみ）。マージ判断は人手。

```bash
git -C <リポ> switch -c docs/review-overall-<YYYYMMDD>
git -C <リポ> add "docs/test/レビュー結果/overall-<スコープ>-<YYYYMMDD>.md"
git -C <リポ> commit -m "docs(review): 全体レビュー結果 (<スコープ>)"
git -C <リポ> push -u origin docs/review-overall-<YYYYMMDD>
```

### 8. 標準出力に JSON パスを 1 行

## 重大度の基準

- **BLOCK**: 実装漏れ・設計逸脱（設計⇔実装の片落ち、設計を経由しない FE⇔BE の暗黙合意を含む）、認可突合の不一致、テナント越境・IDOR の具体箇所、単体テストが皆無の AC、機微情報漏えい・ハードコードシークレット
- **SUGGEST**: 実装パターンの不統一、重複実装（リポ内・リポ間の二重定義）、RTM の部分的な対応漏れ、区分網羅の不足、命名・構成のばらつき、FE 表示制御と権限マトリクスの軽微なずれ
- **NIT**: フォーマッタで直る範囲、軽微な誤字
- 推測で BLOCK にしない。根拠（具体ファイル名・行番号・設計書の該当箇所）を明示できないものは SUGGEST にする。

## 出力 JSON スキーマ

review-requirements と同じ構造。`phase: "overall"`、`iteration` は常に `1`（ループなし）。`findings[].path` は親アンブレラからの相対パス（リポ名前置。例: `claude-poc-backend/src/...`）。`category` は次を使う:
`design_coverage | design_mismatch | cross_issue_consistency | cross_repo_consistency | type_consistency | duplication | architecture | security | authorization | traceability | rtm_gap | naming | error_handling | quality_gate | style | typo | startup_wiring | validator_type_compatibility | controller_test_style`

## 注意事項

- **このスキルではコード・設計書・マトリクスを書き換えない**（diagnostics のみ。出力はレビュー結果 md と JSON だけ）。各リポの `.claude/rules/` は読み取り参照のみ（正典保護）。
- **CI で担保済みの事項を再指摘しない**: UT 実行・カバレッジ閾値・静的解析の通過、PR レビュー、コミットの Issue 参照は implement-loop（CI）の品質ゲートで Issue ごとに担保済み。本工程でローカルにレポート（`target/` `coverage/` 等）が無くても指摘しない。CI の通過状況を参照したい場合は `gh run list` / PR の checks を見る（任意・情報としてのみ）。
- 技術スタック固有の規約はこのスキルに再掲せず、各リポの `.claude/rules/` を実行時に Read して突合する（二重管理の禁止。矛盾時は frontend ルールが正）。
- 既往の Issue 単位レビュー（`docs/test/レビュー結果/implement-issue-*.md`）で「見送り」と判断済みの指摘は重複起票せず、参照に留める。
- `message` / `suggested_fix` などの自然言語フィールドで語句を強調する場合は、ASCII の `"..."` ではなく **鉤括弧 `「...」`** を使う（JSON エスケープ漏れ事故防止、過去事例あり）。
