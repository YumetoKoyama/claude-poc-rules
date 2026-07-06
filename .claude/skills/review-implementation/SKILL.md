---
name: review-implementation
description: 現在の feature ブランチの実装差分（コード + 品質ゲート結果）をレビューし、BLOCK/SUGGEST/NIT の重大度付き JSON を出力する。implement-loop オーケストレータから呼ばれる。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Write
---

# 実装レビュー

> **パス解決（マルチリポジトリ対応）**:
> - **読み取り入力（docs リポジトリ＝claude-poc-docs）**: `docs/requirements/`・`docs/design/` は docs リポジトリ ルート相対。docs をカレントで実行ならそのまま、親アンブレラからなら `claude-poc-docs/` を前置、CI で workflow が追加チェックアウトした docs があればそのパス、無ければ Issue 本文の埋め込み設計を使う。
> - **書き込み出力（own リポジトリ）**: review JSON（`.skills-state/implement/round-<N>-review.json`）は own リポジトリ直下（gitignore 対象・ephemeral）。レビュー結果.md への追記・commit/push はオーケストレーター（implement-loop）が担当する。

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4 における **review** 段を担当します。

**`context: fork` 必須**: produce skill（`/implement-from-issue`）の判断に引きずられず、コード差分と品質ゲート結果だけで独立評価するため。
> **判定の独立性（厳守）**: 以下の理由で BLOCK の深刻度を下げてはならない。
> - 「前ラウンドで指摘済みだから」「fix が試みられたが不完全だから SUGGEST に格下げ」
> - 「escalate（人手介入）を避けるため」「残り回数が少ないから」
> - 「ループの最終回だから通してあげる」
>
> 各指摘は**今回の成果物の品質だけ**で判定する。過去の経緯・ループの進行状況・後続フェーズへの影響は一切考慮しない。state.json の iteration 値はファイル名決定にのみ使い、判定基準に影響させない。
>
> **禁止行為**:
> - 前ラウンドの review JSON（`round-*-review.json`）を Read しない
> - 前ラウンドの指摘が対応されたかを確認しない（それは verify-fix の責務）
> - レビュー結果.md を Read しない（追記はオーケストレーターの責務）
> - 標準出力に JSON パス以外（サマリ・対応確認・統計等）を出力しない

## 役割

feature ブランチの実装差分・設計書との整合・品質ゲート(UT / 静的解析)の通過状況を観点別にレビューし、機械可読 JSON を生成する。

## 入出力

- 入力: 現在の feature ブランチ（`git diff main...HEAD`）
- 入力: 対応する Issue の設計書（`docs/design/` 配下の関連ファイル）
- 入力: 品質ゲートの実行結果（`build/` `target/` `coverage/` 等のレポート）
- 出力: `.skills-state/implement/round-<N>-review.json`（own リポ直下・gitignore）
- 出力（標準出力）: 生成した review JSON のパスを 1 行


## 手順

1. **iteration を取得**: `bash .claude/skills/_common/scripts/get-review-iteration.sh implement` を実行し、stdout の数値を `N` とする。出力ファイル名を `round-<N>-review.json` とする。state.json を直接 Read してはならない（判定の独立性のため）。
2. **差分の特定**: `git diff --name-only main...HEAD` で変更ファイル一覧を取得。
3. **関連設計書を特定**: state または Issue 本文から SCR-XXX / API 名 / テーブル名を抽出し、`docs/design/` の該当ファイルを Read。**あわせて横断設計書 `docs/design/共通部品設計.md` を必ず Read し、定義済み共通部品（GlobalExceptionHandler / 共通バリデーション / 共通レスポンス整形 / ロギング / `JwtUtil` / `apiClient.ts` 等）の一覧を把握する（`common_component` 観点の照合先）。** **レビュー対象がフロントエンド（claude-poc-frontend）の場合は、あわせて `.claude/rules/frontend-*.md`（特に `frontend-routing.md` の認可制御3層・`frontend-99-contract-auth-deps.md`・`frontend-state-api.md`・`frontend-directory-structure.md`・`frontend-coding-rules.md`）を Read し、FE 確定規約を把握する（`frontend_convention` 観点の照合先。正典は frontend ルール）。**
4. **品質ゲート結果の確認（内容依存判定・RC-07）**: レポートの **更新時刻には依存しない**（時刻照合は古いレポートの再利用で欺けるため廃止）。代わりに各レポートに記録された **対象コミットハッシュ／対象ファイルハッシュ** を `git diff main...HEAD` の現在の HEAD・差分ファイルと照合し、**現在のコードに対して実際に実行されたレポートか**を内容で確認する。
   - 判定: ①レポートが**存在しない** → category=`quality_gate` の **BLOCK**（理由「レポート不在」を別 finding として明記）。②レポートは存在するが記録ハッシュが現 HEAD／対象差分ファイルと一致しない → category=`quality_gate` の **BLOCK**（理由「古いコードに対するレポート（内容不一致）」）。③ハッシュ一致＝現コードに対して実行済み → ゲート通過の前提で中身の評価に進む。
   - レポートに対象ハッシュが記録されていない（旧形式）場合も、内容で実行性を確認できないため **BLOCK** とする（時刻依存では判定しない。produce 側＝`implement-from-issue` が対象ハッシュを記録する前提）。
   - バックエンド: `mvn test` の最新結果、JaCoCo カバレッジレポート、SpotBugs / Checkstyle / PMD レポート
   - フロントエンド: `npm test` の Vitest / Jest 結果、Istanbul カバレッジ、ESLint / TypeScript 型チェック
   - **決定論チェックスクリプトの実行（必須・別担当が作成。本スキルは呼び出す前提で記述）**: 次を順に実行し、exit 1 は対応 category の BLOCK とする。
     ```bash
     # カバレッジ閾値（確定表 backend-00-stack.md #13 / frontend-00-stack.md #10 と機械突合）
     bash .claude/skills/_common/scripts/check-coverage-threshold.sh <repo-type>   # backend | frontend
     # migration(V*.sql) ↔ tables/*.md ↔ Entity のカラム/型/制約/nullable 突合
     bash .claude/skills/_common/scripts/check-migration-consistency.sh
     # 当該 Issue が触れた API の OpenAPI スキーマ ⇔ BE DTO ⇔ FE 型 の契約突合
     bash .claude/skills/_common/scripts/check-api-contract.sh
     ```
     - `check-coverage-threshold.sh` exit 1 → category=`coverage` の BLOCK。**ファイル/パッケージ単位で未達箇所を列挙**して finding 化する（「全体未達」だけで済ませない）。
     - `check-migration-consistency.sh` exit 1 → category=`design_mismatch` の BLOCK。
     - `check-api-contract.sh` exit 1 → category=`contract` の BLOCK。
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
8. **review JSON を機械生成**:
   ```bash
   bash .claude/skills/_common/scripts/format-review-json.sh implement \
     .skills-state/implement/round-<N>-findings.tsv \
     .skills-state/implement/round-<N>-review.json \
     --aspects .skills-state/implement/round-<N>-aspects.tsv \
     --summary <summaryファイル(任意)> \
     --merge-json <check-*.shのfindings JSONファイル>...
   ```
   生成とスキーマ検証は機械化されているため、JSON の自己修正リトライは不要。TSV 形式エラー（exit 1）の場合のみ該当行を直して再実行する。
9. **標準出力**: 最終行に **review JSON の相対パスのみ** を 1 行で出力する（orchestrator がパース）。レビュー結果.md への追記・commit/push はオーケストレーターが担当するため、本スキルでは行わない。

## レビュー観点

### BLOCK

- `quality_gate`: 単体テスト・静的解析のいずれかが**失敗**（E2E は品質ゲート対象外。AWS 環境構築後に E2E リポジトリの別工程）
- `coverage`: バックエンドカバレッジが確定表 #13 の閾値（命令(INSTRUCTION)100% / 分岐(BRANCH)90%、いずれも除外後）を下回る（＝`mvn verify` の jacoco:check が落ちる水準）、フロントエンドが確定表 #10（100%、除外後）を下回る、または明確な未テストパスがある。閾値の正典は各確定表（`backend-00-stack.md` #13 / `frontend-00-stack.md` #10）であり、CLAUDE.md は閾値を持たない。`/coverage-to-100` は不足時の改善手順（旧「80%」基準は廃止）
- `design_mismatch`: 実装が設計書と矛盾（API パス・メソッド・スキーマの不一致、テーブル定義との不整合）。**拡張（ADD-8）**: DB マイグレーション（Flyway/Liquibase の `V*.sql`）↔ `docs/design/tables/*.md` ↔ Entity の **カラム名・型・制約（NOT NULL / UNIQUE / FK）・nullable** が三者一致しているか（`check-migration-consistency.sh` の結果も取り込む）。設計で `version` 列が要求されているのに Entity に `@Version` が無い場合も BLOCK
- `contract`: 当該 Issue が触れた API について、**OpenAPI スキーマ ⇔ FE の TypeScript 型 ⇔ BE の Request/Response DTO** の **フィールド名・型・nullable/必須が不一致**（2026-06-12）。Jackson の getter 名ベースシリアライズによる実 JSON フィールド名の乖離（DTO `errorCode` ⇔ FE が読む `code`／`details[].reason` 等）を含む。`check-api-contract.sh` の exit 1 もここに取り込む
- `dead-field`: 設計上、画面で使うはずのレスポンスフィールドを FE が**使用せず**、空文字・固定値・`|| 'デフォルト'`・`?? ''` 等で代替して握り潰している（データ連鎖の断絶を実装側のワークアラウンドで隠蔽。2026-06-12 の核心バグ＝`LoginResponse` 欠落→`setAuth({userId:'',tenantId:'',userName:''})` の再発防止）。`grep` で `|| '` / `?? ''` / `= ''` 代替や、API レスポンス型に存在するのに参照されないフィールドを検出する
- `concurrency`: 状態遷移・先着・上限・二重防止を持つエンドポイントに `@Version`（楽観ロック）/ `@Lock(LockModeType.PESSIMISTIC_WRITE)`（悲観ロック）/ 条件付き UPDATE のいずれも無い（RC-01）。または `GlobalExceptionHandler` に `OptimisticLockException` / `DataIntegrityViolationException` → **409 Conflict** のマッピングが無い
- `security-baseline`: セキュリティ設計値と実装の **機械突合**（RC-05）。BCrypt コスト≥12 / 時刻は `Clock` 注入（`Instant.now()` 直書き禁止）/ パスワードリセットにレート制限 / メール送信が `@Transactional` の外（外部 I/O を tx 内で行わない）/ JWT 失効方針が設計どおり（STATELESS なら logout はクライアント破棄、要失効ならブラックリスト実装）/ ログイン試行ロックの保存先が設計と一致（DB か Redis のいずれか単一）/ メールアダプタ（EXT-001）が**実配線**（スタブ放置でない）。いずれか不一致は BLOCK
- `layer-violation`: レイヤ規約違反の機械検出（RC-04）。`application/` 配下で `import org.springframework.security`（Spring Security 依存）/ presentation 層 DTO の import / 通知 Repository（`*NotificationRepository`）の直接 import、UseCase 内の `subList(`（メモリページング）、ループ内 `save(`（N+1 永続化）を `grep` で検出する
- `security`: OWASP ベースの脆弱性点検（PR 作成前に必須）。SQL インジェクション・XSS・**認可バイパス / IDOR・テナント越境（自社外リソースへの参照・操作）**・JWT 検証漏れ（署名・失効・有効期限）・PII / 機密情報のログ・レスポンス出力・入力サニタイズ漏れ・ハードコードされたシークレット。`docs/design/セキュリティテスト観点.md` の観点と対応づけ、未対応があれば BLOCK。**強化（RC-03＋2026-06-12）**: ①当該 Issue が触れた全 operationId の `@PreAuthorize` が `認可設計.md` / `セキュリティ設計.md` の必要ロールと一致しているか機械的に確認する。②認可設計上ロール限定が必要なエンドポイント（合意・ユーザー追加・状態遷移等）が `isAuthenticated()` のみ／無防備なら BLOCK。③越境レスポンスは **404 に統一**（自テナント内の権限不足は 403）されているか。④**テナントフィルタは SELECT だけでなく UPDATE / DELETE / COUNT / 集計クエリ にも適用**されているか（漏れは BLOCK）。⑤認可は `@PreAuthorize` に集約し、UseCase 内の手書きロールチェックとの二重管理が無いか。**XSS 強化（2026-06-25）**: XSS については以下を必ず確認する:
  - **バックエンド**: プレーンテキストと定義された全 DTO フィールドに `@Pattern(regexp = "^[^<>]*$")` が付与されているか（`grep -rn "@Pattern" src/` で確認）。付与漏れがあれば BLOCK
  - **バックエンド**: バリデーション違反時に 400 + ErrorResponse（MSG-XXX）が返るテストが存在するか
  - **フロントエンド**: `dangerouslySetInnerHTML` にユーザー入力データを渡している箇所がないか（`grep -rn "dangerouslySetInnerHTML" src/` でゼロであることを確認）。存在すれば BLOCK
  - **フロントエンド**: href・src 等の URL 属性にユーザー入力を使う箇所で `javascript:` を排除しているか
  - **フロントエンド**: CSP ヘッダー（`next.config.js` 等の相当ファイル）が設定されているか（未設定は SUGGEST）
- `architecture`: Controller に業務ロジック、フロントに業務判定、REST 以外の画面描画、`.env` の直接コミット
- `common_component`: 設計済みの共通部品（`docs/design/共通部品設計.md` に定義された GlobalExceptionHandler / 共通バリデーション / 共通レスポンス整形 / ロギング方式 / `JwtUtil` / `apiClient.ts` 等）を**再実装・再発明**している（A-2）。実装差分に共通部品と同責務のクラス/関数（独自の `@RestControllerAdvice` 例外ハンドラ、独自の JWT パース・署名検証、`fetch`/`axios` の素呼び出しによる API クライアント、独自の共通レスポンス整形等）が新規追加され、既存の共通部品を import・利用していない場合は BLOCK。`共通部品設計.md` の部品名を Grep で実装差分と突合し、「設計に存在するのに使われず再発明された」ものを finding 化する。設計→実装の参照チェーン断絶（共通部品設計が Issue 本文・実装の必読対象に届かなかったケース）を検知する観点であり、`duplication`(SUGGEST) より重く扱う
- `frontend_convention`: フロントエンド実装（claude-poc-frontend）が `.claude/rules/frontend-*.md` の確定規約に違反（FE 限定。正典は frontend ルール、本観点は実装差分との機械突合）。次を点検する: ①**認可3層**（`frontend-routing.md`「認可制御の 3 層構成」= middleware.ts / protected/layout.tsx / feature 側）のいずれかが欠落し、保護ルートが無防備またはクライアント側のみのガードになっている。②**トークン保存方式**（`frontend-99-contract-auth-deps.md` R-FA-001/003）違反 = `localStorage`/`sessionStorage` へのトークン保存、Cookie 方式での `credentials:'include'`・CSRF 対策の欠落、レスポンスボディ／store へのトークン保持。③**FE データ充足 / dead-field**（R-FS-001）= 設計で表示と定義した項目（ユーザー名・ロール・テナント名等）を空文字・固定値・プレースホルダで握り潰す。④**ベースURL**（R-FU-001/002）= ホスト名のハードコード、ベースURL を持たない相対呼び出し。⑤**依存の実在性**（R-FD-001）= `frontend-00-stack.md` 未照合の依存追加・実在しないバージョン。⑥**ディレクトリ責務 / 状態管理**（`frontend-directory-structure.md`・`frontend-state-api.md` の禁止事項）違反。`grep` で `localStorage`/`sessionStorage`・トークン保持・ハードコード host・`|| '`/`?? ''` 代替・各ルールの禁止パターンを実装差分と突合し、違反を BLOCK とする。FE カバレッジ閾値は `coverage`（確定表 `frontend-00-stack.md` #10）で別途判定する
- `traceability`: Issue の受け入れ条件 **AC-XXX（AC が無い基盤 Issue は設計書「実装内容」項目）に対応する単体テスト（TC-XXX）が 1 件も無い真のカバレッジ穴**（単体マトリクス・RTM を横串で確認して検出）、またはコミットメッセージに Issue 参照（`#N` / `Refs:`）がない。※マトリクス/RTM の **存在・構造**（ファイル有無・TC 行・Issue 行）は produce 段のハードゲート `check-test-matrix.sh ... unit` が担保するため、本観点は **単体カバレッジの中身** を見る。結合テスト（IT）のカバレッジは結合テスト工程のレビューが担当
- `git`: `main` / `master` / `develop` への直接 commit、`.github/workflows/**` の編集（deny ポリシー違反）

### SUGGEST

- `readability`: 関数が長すぎる（>50 行）、ネストが深い（>4 段）、命名が説明的でない
- `duplication`: 同じロジックの複数箇所重複（DRY 違反）
- `error_handling`: 例外ハンドリングが粗い（catch して握り潰し、ログだけ）
- `performance`: N+1 クエリ、不要なレンダリング、未使用 import
- `pagination`: 一覧系 API・クエリの**全件取得**（ページング未実装・上限なし `findAll`）による負荷リスク（2026-06-12）
- `i18n`: ハードコードされた日本語メッセージで国際化未対応（要件で求められている場合）
- `test_design`: 単体マトリクスは **存在する前提**（存在・構造はゲートが担保）で **中身の質** を見る。AC（または実装内容項目）↔ TC-XXX の対応が意味的に妥当でない、正常系 / 異常系 / 境界値 / 権限境界 の **区分網羅が不足**、テスト対象（Service / Validation / 例外）の観点が薄い。※AC に対応する単体テストが **皆無** の場合は SUGGEST ではなく BLOCK（`traceability`）。**結合テスト（IT）の設計品質は本レビューの対象外**（結合テスト工程で評価）
- `traceability_matrix`: RTM は **存在し当該 Issue 行がある前提**（存在・Issue 行はゲートが担保）で、**単体の横串カバレッジ漏れ** を見る。RTM 上で UC / AC / SCR に対し TC-XXX の対応が部分的 等。※RTM の横串で単体テストの無い AC を発見した場合は BLOCK（`traceability`）。IT-XXX / E2E-XXX 列の整備は各別工程が担当し、本レビューでは未記入でも指摘しない
- `nonfunc_test`: 設計 `docs/design/非機能テスト計画.md` に定義された非機能要求値（性能・負荷・可用性）の検証が、該当する実装変更に対して計画・実施されていない
### NIT

- `style`: フォーマッタが直せる範囲（Prettier / Spotless で吸収可能）
- `typo`: コメント・変数名の軽微な誤字

## 出力 JSON スキーマ

review-requirements と同じ（`related_files` 含む）。`phase: "implement"`、`category` には上記カテゴリを使う。`related_files` には指摘対象ファイル（`path`）以外に整合確認が必要な関連ファイルを記載する。

`checked_aspects` / `uncovered_areas`（P-10）: `format-review-json.sh` が aspects TSV から生成するフィールド。`checked_aspects` は検査した観点の一覧（aspect/status/method/note）、`uncovered_areas` は status が `checked` 以外だった観点（未検査・部分検査とその理由）の一覧。**PASS はこのリストが揃って初めて解釈可能** であり、findings が 0 件でも `uncovered_areas` に重要観点が残っていれば「検査していないだけ」の可能性がある。採択者は `uncovered_areas` を見て残リスクを判断する。

## 注意事項

- このスキルではコードを書き換えない（diagnostics のみ）。
- 品質ゲートが**実行されていない**場合は、それ自体を `BLOCK` category=`quality_gate` として報告する。
- 差分が巨大（>30 ファイル）の場合は、サマリで「巨大変更につき抜本見直しを推奨」と明記。
- `message` / `title` / `recommendation` などの自然言語フィールドで語句を強調する場合は、ASCII の `"..."` ではなく **鉤括弧 `「...」`** を使う。JSON 文字列内の `"` エスケープ漏れ事故を減らすため（過去発生事例あり）。
