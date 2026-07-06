# Web アプリ開発ガイダンス（React / Spring Boot）

このリポジトリは、フロントエンドを TypeScript（React）、バックエンドを Java（Spring Boot）で構成する Web アプリケーションを Claude Code で設計・実装・検証するための共通設定を提供します。

## CI 到達性の大原則（最重要・RC-13）

> **CI で走るフェーズに効かせるルールは、必ずスキル本文・子リポジトリの `.claude/rules/`・`_common/scripts/` に置く。親 `claude-poc-rules` の CLAUDE.md「単独」への記載は禁止する。**

- CI（GitHub Actions の implement / fix / review / test）は **子リポジトリ＋`claude-poc-docs` を基本としてチェックアウト**し、親 `claude-poc-rules` の CLAUDE.md・`rules/` を**持ち込まない**。したがって親 CLAUDE.md だけに書いたルールは CI 上で静かに無効化される。（例外: 設計フェーズの `claude-design-from-issue` は技術スタック確定ゲートのため FE/BE の `.claude/rules` のみを追加 sparse checkout する。L-10）
- よって本ファイル（親 CLAUDE.md）の役割は次の 2 つに限定する:
  1. **人間向けの開発フロー索引**（各フェーズの順序・成果物・採択ゲートの全体像）。
  2. **ローカル専用オーケストレーション**（親アンブレラから手動起動する際の採択確認・マージ済みチェック等。CI には存在しない手順）。
- CI 到達が必要な規約（ID 規約・テスト 3 層・セキュリティ観点・界面契約・並行制御・data-sufficiency など）は、下記の **共有正典ブロック（`shared-canon`）** に集約し、これを**各子リポジトリの CLAUDE.md へ自動生成で配布（commit 済み）**する。あわせて親 `rules/cross-cutting.md` を各子の `.claude/rules/cross-cutting.md` へ同期配布する（手コピー禁止・symlink / サブモジュール / CI 同期）。同期検査は `_common/scripts/check-claude-md-sync.sh`（推奨・CI）で行い、不一致なら fail。
- **state は必ずスクリプト経由で更新する（手編集禁止）**: `.skills-state/<phase>/state.json` は `init-state.sh` / `advance-state.sh` / `record-review.sh` のみが書き込む。Claude・skill が JSON を直接 Edit/Write してはならない（RC-08）。

<!-- shared-canon:start -->
<!--
  共有正典ブロック（CI 必須の最小規約）。
  本ブロックは親 CLAUDE.md が正典。各子リポジトリの CLAUDE.md には本ブロックと
  一字一句同一の内容を自動生成で埋め込む（手転記禁止）。
  CI は親を持ち込まないため、ここに置いた規約だけが子リポ単体チェックアウトでも有効になる。
  同期検査: _common/scripts/check-claude-md-sync.sh
-->

### 1. ID・採番・凡例規約

- ID は「英字プレフィックス + 3 桁ゼロ埋め連番」とする。主な体系: `SCR-`（画面）/ `UC-`（ユースケース）/ `ACT-`（業務アクティビティ）/ `AC-`（受け入れ条件）/ `BR-`（業務ルール）/ `ENT-`（概念エンティティ）/ `ST-`（状態）/ `EXT-`（外部 IF）/ `MIG-`（移行）/ `MSG-`（メッセージ）/ `SEQ-`（シーケンス）/ `TC-`（単体テスト）/ `IT-`（結合テスト）/ `E2E-`（E2E テスト）。
- 要件・設計・テストで**同じ ID を引用**して縦串トレースを成立させる。
- 例外（AC のみ・2026-07-03 改訂）: `AC-XXX` は**機能スコープ採番**を正式採用する。機能をまたいで参照する場合は必ず `機能名/AC-XXX` で修飾し、RTM の主キーも同形式とする（非修飾のクロス参照は `check-id-uniqueness.sh` が BLOCK）。
- ID・略号を導入する文書は冒頭付近に**凡例（略号一覧表）を必ず置き**、新規略号追加時に凡例も更新する。

### 2. テスト 3 層と RTM

- テストは **単体（TC-XXX）/ 結合（IT-XXX）/ E2E（E2E-XXX）** の 3 層で設計する。各テストは **正常系 / 異常系（入力エラー）/ 境界値 / 権限境界** の区分を明示する。
- 受け入れ条件（AC-XXX）ごとに少なくとも 1 つの実行可能テストを対応づける。
- 要件→設計→Issue→テストの追跡は **RTM（トレーサビリティマトリクス）** に 1 表で集約する（列: UC / AC / BR / SCR / API operationId / Issue# / TC-XXX / IT-XXX / E2E-XXX）。
- 単体マトリクス(TC)・RTM は**製造フェーズ**、結合マトリクス(IT) は**結合テスト工程**の成果物（実施タイミングが異なるため工程を分ける）。

### 3. セキュリティレビュー観点（OWASP ベース）

- 認可バイパス・IDOR / テナント越境・JWT 改ざん・機微情報のレスポンス/ログ漏えい・入力サニタイズを必須観点とする。
- **テナントフィルタは SELECT だけでなく UPDATE / DELETE / COUNT / 集計クエリにも適用**する（全クエリ種別の網羅を確認）。
- **テナント越境は 404、自テナント内の権限不足は 403** に応答コードを統一する。
- 認可は `@PreAuthorize`（BE）に集約し、各 operationId の必要ロールが認可設計と一致することを突合する。

### 4. 界面契約の単一正典（`_common.yaml`）

- API / エラー / コード値の界面契約の正典は `docs/design/api/_common.yaml`（ErrorResponse・PageMeta・コード値 enum）とする。共通部品設計・各 YAML・実装・FE はこれを参照し、**JSON 上の実フィールド名（`code` / `details[].reason` 等）を一字一句一致**させる。`frontend ルール最優先` は **FE 内部実装規約に限定**し、界面契約は設計書を正とする。
- コード値（enum）は **4 層で統一**する: 要件 `コード値定義.md` → 設計 `_common.yaml` → BE enum → FE const。値・表示名がすべての層で一致すること。

### 5. 並行制御（必須）

- 状態遷移を持つ集約（ステータス・カウンタ・先着・上限を持つエンティティ）は、設計で**並行制御方針（楽観 `@Version` か悲観 `FOR UPDATE`）と DB 一意制約**を必ず明記する。
- 業務ルールの「先着」「上限 N」「二重不可」は、アプリ層の read-modify-write ではなく **DB 一意制約／条件付き UPDATE／行ロック**で保証する（非正規化カウンタ単独での上限判定を禁止）。

### 6. data-sufficiency（画面表示項目 ↔ API 対応の原則）

- 画面設計で「表示する」と定義された**全データ項目**および業務判定に使う値（自他判定・権限判定用の ID 等）は、供給元 API（operationId × レスポンスフィールド）が存在し、画面 md の API 欄に取得経路が明示されていなければならない。
- API のパス変数・クエリパラメータは、その値の出所（前画面のどの項目・どのレスポンスフィールドか）が画面遷移・シーケンスのどこかに現れること。
- 供給元が無い表示項目・出所不明のパラメータは**設計の BLOCK**として扱う。

### 7. オープン課題のクローズ規約

- `Q-NF*`（セキュリティ・運用ベースライン）・`Q-DM*`（データモデル）・`Q-EI*`（外部 IF）・`Q-MIG*`（移行）に該当する課題は**設計フェーズ起動前に closed** にする（要件採択者の責務）。
- `オープン課題.md` の冒頭に「設計着手前にクローズ必須の課題区分」と「設計フェーズへ持ち越して良い課題区分」を明示する。

<!-- shared-canon:end -->

## 開発フロー（skill オーケストレーション）

本プロジェクトは **skill だけでオーケストレーション** する。各フェーズに **`*-loop` orchestrator skill** があり、`produce → review → fix → review` を上限まで自動で回す（Pattern 4: Iterative Loop。上限は `init-state.sh` の第 3 引数で制御）。設計の根拠は [docs/architecture/skill-orchestration.md](docs/architecture/skill-orchestration.md)。

```
1. /requirements-loop <要件素材ファイル/メモ>
   └─ produce: /requirements-from-input が docs/requirements/ を生成
        ├─ 概要.md / 業務ルール.md / functional/[機能名].md
        ├─ ユースケース図.md / activities/[フロー名].md
        ├─ 画面一覧.md / データモデル.md / 外部インターフェース一覧.md / 移行要件.md
        ├─ 権限マトリクス.md / メッセージ一覧.md(MSG) / コード値定義.md / 通知・文面定義.md
        ├─ 非機能要件.md / ブランドガイドライン.md
        ├─ 用語集.md / オープン課題.md
      review : /review-requirements が BLOCK/SUGGEST/NIT を JSON 出力
      fix    : /fix-requirements が BLOCK + SUGGEST + NIT を反映
      → PASS（BLOCK == 0 かつ SUGGEST == 0）または上限到達で ESCALATE

2. 人手レビュー（要件定義の採択）
   └─ 採択前は設計・製造・テスト・Issue 起票のいずれにも進まない
   └─ 採択手順は docs/process/11-adoption-checklist.md に従う（Q クローズ → 確定値の本文反映 → check-closed-reflected / check-id-uniqueness / check-open-issues 全緑 → main コミット。R-02/R-05）

3. /design-loop [docs/requirements/]
   └─ produce: /design-from-requirements が docs/design/ を生成
        ├─ 概要.md / screens/画面遷移.md / screens/共通レイアウト.md / screens/[scr-id]-*.md
        ├─ api/_common.yaml / api/[リソース名].yaml（OpenAPI 3.1、リソースごとに 1 ファイル）
        ├─ IF定義.md / DB定義.md / tables/[テーブル名].md
        ├─ 方式設計.md / セキュリティ設計.md(認可設計を内包or分割) / バッチ設計.md / 共通部品設計.md(BE) / フロントエンド共通設計.md(FE) / 運用設計.md
        └─ テスト戦略.md / シナリオ戦略.md / 非機能テスト計画.md / セキュリティテスト観点.md
      review : /review-design
      fix    : /fix-design
      ※ 単体テストマトリクス(TC)・トレーサビリティマトリクス(RTM) は製造フェーズで作成（/test-design-from-issue）。結合テストマトリクス(IT) は製造から分離した結合テスト工程（/integration-test-from-design）で設計・実施する

3.5. /humanize-design（P-14）
   └─ 採択レビュー用の設計書ビューを生成。ID 凡例は共通ファイル参照（`_common/references/id-legend.md`）で再掲しない（C-2）。

4. 人手レビュー（設計書の採択）
   └─ 採択前は製造・テスト・Issue 起票のいずれにも進まない
   └─ design-loop PASS 時に RTM 骨格を前倒し生成（`generate-rtm-skeleton.sh`・未カバーは `--report`。P-15）。スコープ外・凍結の判断は Decision Log に D-ID で記録（07-decision-log.md）。

5. /ui-brief-from-design [docs/design/]   ※任意（UI を Claude Design で作る場合）
   └─ 採択済み設計書から、Claude Design（claude.ai/design）投入用の UI ブリーフを生成
        ├─ docs/design/ui-design/brief/_共通.md（DS・共通コンポーネント・ロール・全画面横断のルール）
        ├─ docs/design/ui-design/brief/[scr-id]-[画面名].md（画面ごとに 1 ファイル、_共通.md からの差分のみ）
        └─ docs/design/ui-design/brief/README.md（索引 + Claude Design 投入手順）
      ※ Claude Design へは _共通.md を先に投入し、続いて画面別ブリーフをまとめて添付する。
      ※ 設計書本体は書き換えない。フィードバックループは現状未整備（人手レビュー前提）。

6. Claude Design での UI 生成（人手作業、claude.ai/design）
   └─ _共通.md を最初に投入してデザインシステムを確立 → 画面別ブリーフを一括 or 章単位で添付
      → 対話で調整 → Handoff bundle を Export
      ├─ Export 物は docs/design/ui-design/handoff/ 配下に Export の構造そのまま格納（人手）
      │    docs/design/ui-design/handoff/README.md / prototype/ / tokens/ のように Claude Design の出力を分割しない
      └─ 採択前は後続 Issue 起票・実装に進まない

6.8. /reconcile-handoff-with-design [docs/design/ui-design/handoff/]   ※UI 生成後の整合検証（検出専用・create-issues の前段ゲート）
   └─ Handoff（prototype）と採択済み設計書を突合し、設計外の表示項目・状態・遷移・バリデーション・新規画面・DS/コード値の乖離を BLOCK/SUGGEST/NIT＋対処区分で出力（fix なし・設計/handoff は書き換えない）。検出観点の詳細は skill 本文が正典。
      ├─ 「採用」乖離 → /impact-analysis-from-change → /design-amendment → docs PR 採択 → /reopen-issues-from-amendment
      ├─ 「棄却」乖離 → Claude Design で再調整 → Handoff 再格納 → 本工程を再実行
      └─ BLOCK が 0 件になるまで 7（create-issues）へ進まない（ハードゲート）

7. /create-issues-from-design [docs/design/]
   └─ 設計書 + ui-design/handoff/README.md の scr-id→prototype 関数マッピングを解析し、
      GitHub Issue を画面・API・IF・テーブル単位で起票（画面 Issue には prototype 参照を埋め込む）
      └─ Issue 間の実装依存順序（DB → BE API → FE 画面）を本文に `Depends on: #XX` で明示する（S5）

8. /implement-loop <ISSUE-NUMBER>
   └─ produce: /implement-from-issue が実装・品質ゲート（UT / 静的解析 を Pattern 2 で並列）・テスト設計（単体マトリクス＋RTM を 2 タッチ＝実装と並行ドラフト→実装後に実コード整合で確定。/test-design-from-issue）・PR 作成
      ※ テスト設計の出力は check-test-matrix.sh（phase=unit）のハードゲートを通過しないとコミット/PR に進まない
      ※ 結合テスト(IT) は製造では設計・実施とも行わず、結合テスト工程（/integration-test-from-design）で別途実施する
      ※ E2E は AWS 環境構築後に E2E リポジトリの別工程とし、現環境では実行しない（/e2e-from-design は凍結中）
      review : /review-implementation がコード差分と品質ゲート結果を評価
      fix    : /fix-implementation が同じ feature ブランチに追加コミット

8.5. /integration-test-loop <フィーチャ>   ※製造とは別工程（結合テスト・S3）
   └─ produce: /integration-test-from-design が結合テストマトリクス(IT) の設計と @SpringBootTest + Testcontainers での実施を行い、RTM の IT 列を更新する（該当フィーチャの構成 Issue が組み上がった後。製造の各 Issue からは呼ばない。check-test-matrix.sh（phase=integration）で検証）
      review : 結合テスト結果のレビュー（失敗原因が実装側か設計側かを判定）
      fix    : 実装側の問題なら修正→再テスト。設計側の問題なら ESCALATE（人手の設計変更へ）

8.8. /review-implementation-overall [対象] [フィーチャ名]   ※フィーチャ横断の全体レビュー（S10）
   └─ 起動条件（ハードゲート）: 当該フィーチャの全 Issue が `main` にマージ済み + 結合テスト（8.5）完了後 + feature-completion-check が PASS（全 Issue クローズ / RTM の TC・IT 充足 / 結合テスト実施 / 品質ゲート緑 を横串確認）。条件未充足では起動しない。
      └─ review のみ（fix なし・ループなし）。横断指摘は /create-issue-from-review で Issue 文章を生成し、人手で起票 → 通常の /implement-loop で対応する（自動ループ不要・人手判断）。

9. 人手レビュー（PR レビューと本番マージ判断）

※ 変更発生時のフロー（採択後の要件/設計変更の影響波及・S1）:
   /impact-analysis-from-change   ← RTM ＋設計クロスリファレンスで波及先（設計ファイル・Issue・実装・テスト）を機械特定
   /design-amendment              ← 採択済み設計への差分変更を管理し、変更前後の diff を docs/design/変更履歴.md に追記
   /reopen-issues-from-amendment  ← 設計変更の影響を受ける既存 Issue を再オープン or 追加起票（起票は人手＝採択ゲート）
```

### 改善ループ（Pattern 4）の終了条件

- **review JSON は手書き Write 禁止**（P-08/P-10）: findings は TSV → `format-review-json.sh` で機械生成し、**検査済み観点リスト（checked_aspects）と未カバー領域（uncovered_areas）を必須**で含む。採択者は件数でなく未カバーで残リスクを判断する（正典: `.claude/README.md`「レビューの仕組み」＋各 review スキル本文）。

- `BLOCK == 0` **かつ SUGGEST == 0（全カテゴリ）**を満たした iteration で **PASS** → 次フェーズへ（判定は `record-review.sh` が全 *-loop 工程共通で決定論的に行う）
- 上限まで反復しても BLOCK または SUGGEST が残った場合は **ESCALATE** → 人手レビュー必須
- **全カテゴリの SUGGEST が 1 件でも残れば fix（上限到達後は ESCALATE）**し、BLOCK==0 でも素通りさせない（RC-08）。判定は `record-review.sh` に一元実装（CLAUDE.md 単独記載に依存しない＝CI でも有効。RC-13）。閾値は環境変数 `SUGGEST_THRESHOLD`（既定 0＝SUGGEST が 1 件でも残れば PASS させない）。NIT も fix 対象に含める（極力対応。スキップ時はレビューマーカーを残す）。
- **全 *-loop 工程（requirements / design / implement / integration）で SUGGEST・NIT 扱いは共通**: review が BLOCK/SUGGEST/NIT を出力 → fix が BLOCK+SUGGEST+NIT を反映し（スキップした指摘のみレビューマーカーを残す）→ 終了条件は上記の `record-review.sh` で一元判定。一方 **`review-implementation-overall`（横断レビュー）は *-loop ではない**ため、その SUGGEST/BLOCK は自動 fix せず `create-issue-from-review` で Issue 化して人手判断に回す（別経路。RC-08/S10）。
- 状態は `.skills-state/<phase>/state.json` に保持される（gitignore 対象）。**state は `init-state.sh` / `advance-state.sh` / `record-review.sh` のスクリプト経由でのみ更新し、手編集（Claude・skill による直接 Edit/Write）を禁止する**。`advance-state.sh` は max_iterations 超過ガードと state スキーマ検証を行い、超過時は escalate へ遷移する。state 不在のままの review は無効（必ず loop 経由で初期化する）。

## 共通応答ルール

- ユーザーへの応答、要件定義書、設計書、作業ログ、説明文は、明示的な指定がない限り日本語で記述する。

## ドキュメントの正典（Source of Truth）

開発フローに関する記述は複数の文書に分散しているため、役割を次のとおり固定する。矛盾を見つけたらこの優先順位で解消し、重複記述は片方を参照に置き換える。

- **開発フローの正典**: 本ファイル（CLAUDE.md）。各フェーズの順序・成果物・ルールはここを最上位とする。
- **設計根拠**: `docs/architecture/skill-orchestration.md`（skill 連鎖の設計思想・状態機械・採択ゲート・整合チェック）。
- **運用手順の詳細**: `docs/process/`（レビュー基準・Issue 管理などの運用ガイド）。
- **意思決定の記録と計測**: 横断判断（スコープ外・凍結・採否）は `docs/process/decision-log.md` に D-ID で記録（運用: `07-decision-log.md`）。各 *-loop の実績は `loop-metrics.sh` で `docs/process/metrics/` に集計（P-17）。
- **技術スタックの正典**: 各子リポジトリの `.claude/rules/`（FE: `claude-poc-frontend/.claude/rules/frontend-*.md` / BE: `claude-poc-backend/.claude/rules/backend-*.md`）。フレームワーク・ライブラリ・バージョンはここにのみ記載し、CLAUDE.md・設計書・スキルは再掲せず参照する。矛盾時は frontend ルールを最優先（正）とする。親 `rules/` には横断 AI ルール（`rules/cross-cutting.md`）のみを置く（`docs/process/リポジトリ構成と移行計画.md`）。
- **正典の保護（機械的強制）**: 親 `rules/` 配下・親 CLAUDE.md・各子リポジトリの `.claude/rules/` 配下は **Claude 実行中の編集を禁止**する（`.claude/hooks/protect-canon.sh` が PreToolUse で Edit/Write/MultiEdit/Bash 書き込みをブロック。パターン `(^|/)rules/` は子の `.claude/rules/` にも合致する）。正典の変更は人手で行う。Claude に編集を手伝わせる場合のみ、`ALLOW_RULES_EDIT=1` を設定したセッションで実行する。スキルの自動実行はフラグを立てないため常にブロックされ、ルールを書き換えて品質ゲートを通すことはできない。
- **正典への改善反映（P-09）と 3 系統同期（P-13）**: 正典への改善は直接編集せず `/propose-canon-patch` で差分提案→人手適用（正典: `canon-proposals/README.md`）。スキルは親 generic / FE / BE の 3 系統管理で、意図的分岐は `lineage-manifest.txt` 宣言制・検知は `check-skills-lineage-sync.sh`（正典: `docs/process/08-skills-lineage-sync.md`）。
- **Agent Teams（experimental の teammate 機能）は使用しない**（RC-09）。並列実行は Pattern 2（Parallel Fan-Out）で代替する。`.claude/settings.json` から `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` と `teammateMode` を**削除**して本方針と整合させる（旧 settings に残っていた両キーは矛盾のため除去済み）。`defaultMode` は `bypassPermissions` とし、危険系操作は deny で明示的に封じる。

## CI/CD セキュリティ方針（RC-12）

- 正典は `docs/process/09-ci-security.md`（発火制限・`pull_request_target` 回避・起票ワークフロー制限）。CI 雛形として固定し `create-issues` / bootstrap で配布する（親 CLAUDE.md 単独記載では CI 非到達のため、雛形＝子へ配布される成果物に多重化する）。

## 技術スタックの正典と確定ルール

技術スタックは要件で**人間が指定する**。Claude は既定値で自動補完しない。未指定・未確定のまま設計・製造フェーズに進まない（**ハードゲート**）。

- 正典は各子リポジトリの `.claude/rules/[fe|be]*-00-stack.md`（技術スタック確定表）。CLAUDE.md・設計書・スキルはフレームワーク名・バージョンを**再掲しない**（二重管理の禁止）。矛盾時は **frontend ルールを最優先（正）** とする。
- **機械的強制**: `design-loop` / `design-from-requirements` は開始前に `check-stack-decided.sh` を実行し、`要確定` 残存・確定表不在（未記載 = 要確定）なら exit 1 で設計着手をブロックして未確定項目を人間に提示する。既定値による自動決定は禁止。
- 詳細（対象ファイルの所在・確定手順・横断決定の記録先）: `docs/process/10-stack-rules.md`（2026-07-02 に本節から移設。内容不変）。

## 開発ルール

> **注（RC-13・重複排除）**: 各フェーズ成果物の**作成規約（採番 ID・Mermaid 図種別・必須記載項目・「無い場合も明記」等）は、CI が読み込む produce スキル本文＋ガードレールが正典**。本ファイルでは再掲せず参照に置き換える（「ドキュメントの正典」§の方針）。横断規約（ID 体系・テスト 3 層・界面契約・並行制御・data-sufficiency・オープン課題クローズ）は **shared-canon §1〜7** が正典。

### フェーズ分離と採択ゲート（親 CLAUDE.md の正典範囲）

- 実装前に要件定義・設計書を確認する。要件定義（`docs/requirements/`）が無ければ先に `/requirements-from-input` を実行する。
- 各フェーズはそのフェーズの成果物だけを作る: 要件フェーズで設計・実装・テストに踏み込まない／設計フェーズで要件の意思決定（業務ルール追加・画面新設・用語定義）をしない／設計は人手採択後にのみ製造・テストへ進む。
- **採択ゲートは人間の明示アクションで強制する**（証跡は GitHub）。要件・設計の採択 = docs リポジトリ（`claude-poc-docs`）の `main` への PR マージ（前提: `main` に branch protection）。マージを契機に `create-issues-from-docs` workflow が後続 Issue を自動起票する。**実装の開始 = 人間が対象 Issue に `@claude` とコメント**であり、Claude・skill が自らコメント／マージして起動してはならない。ローカル（親アンブレラ）から後続 skill を起動する場合は入力ドキュメントが docs `main` にマージ済みかを確認し（`git log origin/main -- <パス>`）、未マージなら中断して人手採択を依頼する。ループの `passed=true`（BLOCK==0）は採択ではない。
- 既定配置: 要件＝`docs/requirements`、設計＝`docs/design`、テスト＝`docs/test`。
- 変更は差分が追いやすい加算型を優先し、無関係なファイルは書き換えない。

### 成果物の作成規約（正典は produce スキル本文・再掲しない）

- 要件成果物（ユースケース図/UC・業務アクティビティ/ACT・概念データモデル/ENT・ST・外部 IF/EXT・移行/MIG・権限マトリクス・メッセージ/MSG・コード値定義・通知文面・非機能要件）: `.claude/skills/requirements-from-input/`（+ template）と `.claude/skills/requirements-guardrails/`（ネガティブパターン・非機能テンプレ・文書間整合）。未確定値は本文に断定で書かず `オープン課題.md`（`Q-NF*`/`Q-DM*`/`Q-EI*`/`Q-MIG*` 等）へ切り出し設計着手前にクローズ（shared-canon §7）。
- 設計成果物（画面/SCR・共通レイアウト・画面遷移・シーケンス/SEQ・OpenAPI 3.1〔`api/[リソース].yaml` + `_common.yaml`〕・DB定義/tables・方式/セキュリティ〔認可〕/バッチ/共通部品(BE)/フロントエンド共通(FE)/運用設計）: `.claude/skills/design-from-requirements/`（+ template）と `.claude/skills/design-guardrails/`。
- テスト設計: 単体 TC・RTM は `.claude/skills/test-design-from-issue/`、結合 IT は `.claude/skills/integration-test-from-design/`（3 層・区分・RTM 列は shared-canon §2 が正典）。

### UI（Claude Design）連携

- 設計採択後に `/ui-brief-from-design` で `docs/design/ui-design/brief/`（`_共通.md` + 画面別）を生成 → Claude Design で UI 生成 → Export を `docs/design/ui-design/handoff/` に **Export 構造そのまま**（`README.md`/`prototype/`/`tokens/`）人手格納 → `/reconcile-handoff-with-design` で突合（6.8）→ 採択後に `/create-issues-from-design`。scr-id ↔ prototype 関数の対応は `handoff/README.md` のマッピング表を Source of Truth とし、画面 Issue へ埋め込む。設計書本体・handoff は書き換えない。詳細手順は各 skill 本文。

### 実装規約（正典は子リポジトリの `.claude/rules/`・再掲しない）

- FE/BE の実装規約（アーキテクチャ・レイヤー・パッケージ・命名・状態管理・API 連携・ルーティング・認可・テスト）は `claude-poc-frontend/.claude/rules/frontend-*.md`・`claude-poc-backend/.claude/rules/backend-*.md` に従う（矛盾時は frontend ルールが正）。FE/BE 境界は OpenAPI 3.1 の REST API、認証は JWT 等トークンベースで CORS を明示。BE は画面描画を持たず JSON REST のみ、表示ロジックは単純に保ち業務判定は BE Service へ寄せる。採用技術スタックは設計着手前に各子 `.claude/rules/` で確定（ハードゲート・「技術スタックの正典と確定ルール」§）。
- DB 変更は明示 migration を作成し Entity/Repository/DDL/`docs/design/tables/*.md` を整合させる。**デモ期間の例外**（`ddl-auto` 許容・migration 免除と解除条件）は `claude-poc-backend/.claude/rules/backend-00-stack.md` #8 を正典とする（矛盾時は #8 が正）。
