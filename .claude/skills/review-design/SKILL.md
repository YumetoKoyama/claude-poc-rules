---
name: review-design
description: docs/design/ 配下の設計書一式をレビューし、BLOCK/SUGGEST/NIT の重大度付き JSON を出力する。design-loop オーケストレータから呼ばれる。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Write
---

# 設計書レビュー
> **STATE_DIR の解決（D-03・最初に必ず 1 回）**: `STATE_DIR="$(bash .claude/skills/_common/scripts/state-dir.sh design)"` を実行し、以降の `<STATE_DIR>` はこの絶対パスを指す。`.skills-state/...` の相対パス直書きは禁止（書き手による state 置き場の分裂防止）。


> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4 における **review** 段を担当します。

**`context: fork` 必須**: produce skill（`/design-from-requirements`）の意図に引きずられず、書かれた設計だけで独立判定するため。
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

> **ガードレール適用（必須）**: レビュー観点の根拠として `design-guardrails` スキルの `references/negative-patterns.md`（設計アンチパターン）・`references/consistency-checklist.md`（縦串・データ需給）・`references/security-checklist.md`（セキュリティ必須項目）を適用する（S11）。

`docs/design/` 配下の設計書を網羅的に読み、要件定義との整合 + 設計品質を観点別にレビューし、機械可読 JSON を生成する。

## 入出力

- 入力: `docs/requirements/`（整合確認の参照元）、`docs/design/` 配下の Markdown / YAML
- 出力: `<STATE_DIR>/round-<N>-review.json`
- 出力（標準出力）: 生成した review JSON のパスを 1 行


## 手順

1. **iteration を取得**: `bash .claude/skills/_common/scripts/get-review-iteration.sh design` を実行し、stdout の数値を `N` とする。出力ファイル名を `round-<N>-review.json` とする。state.json を直接 Read してはならない（判定の独立性のため）。
2. **要件定義を Read**: `docs/requirements/概要.md` `業務ルール.md` `functional/*.md` `ユースケース図.md` `activities/*.md` `画面一覧.md` `非機能要件.md` `権限マトリクス.md` `メッセージ一覧.md` `コード値定義.md` `通知・文面定義.md`
3. **設計書を Read**: `docs/design/概要.md` `screens/画面遷移.md` `screens/*.md` `sequences/*.md` `api/_common.yaml` `api/*.yaml` `IF定義.md` `DB定義.md` `tables/*.md` `方式設計.md` `セキュリティ設計.md` `認可設計.md` `バッチ設計.md` `共通部品設計.md` `フロントエンド共通設計.md` `運用設計.md` `テスト戦略.md` `シナリオ戦略.md` `非機能テスト計画.md` `セキュリティテスト観点.md`
4. **観点別にレビュー**: 後述のチェックリスト
4.2. **決定論スクリプトによる機械検証（必須）**: 次を実行し、得られた findings JSON を `<STATE_DIR>/round-<N>-check-*.json` 等の一時ファイルに保存する（`format-review-json.sh` の `--merge-json` で取り込む。手動マージ禁止）。
   - **偽陽性の扱い（D-02・必須）**: 決定論スクリプトの findings を偽陽性と判断しても、手動でマージから外してはならない。`<STATE_DIR>/suppressions.tsv`（`path部分一致\tcategory\tmessage部分一致\t理由\t承認者` の 5 列 TSV）に理由つきで宣言すると `format-review-json.sh` が機械的に除外し、review JSON の `suppressed_findings` に記録する（採択者がレビューできる）。
   ```bash
   # 各スクリプトは独立（共有状態・依存関係なし）なので並列実行で時間短縮する
   bash .claude/skills/_common/scripts/check-openapi-valid.sh docs/design/api/                          &  # OpenAPI 3.1 構文＋$ref 参照先存在（openapi BLOCK 候補）
   bash .claude/skills/_common/scripts/check-contract.sh docs/design/                                   &  # operationId/ErrorResponse/コード値 の文書間突合（contract-consistency 候補）
   bash .claude/skills/_common/scripts/check-doc-lint.sh docs/requirements/ docs/design/                &  # 非日本語混入・表記揺れ・TODO 残置（i18n/NIT 候補）
   bash .claude/skills/_common/scripts/check-db-design-consistency.sh docs/design/                      &  # tables内部完全性 + tables↔api 型/桁/enum + sequences SQL(列存在/INTERVAL値)↔tables 突合（db-schema-completeness / db-contract / db-sequence-consistency 候補）
   bash .claude/skills/_common/scripts/check-migration-consistency.sh                                   &  # migrationが存在すれば tables↔migration 突合（無ければ自動スキップ＝設計段階での前倒し）
   bash .claude/skills/_common/scripts/check-confirmed-values.sh docs/requirements/ docs/design/ docs/requirements/ &  # closed課題(Q-NF*等)の確定値 ↔ 設計/要件記述の数値矛盾（confirmed-value 候補）
   wait  # 全スクリプトの完了を待つ
   ```
4.3. **データ需給表の作成（必須）**: 全画面の表示項目を縦軸に「画面項目 → operationId.フィールド」の対応表を機械的に作り、供給元の無い項目を `data-sufficiency` の BLOCK 候補とする。とくにログイン直後の画面・共通レイアウト（ヘッダー等）の表示項目が `LoginResponse` または `/me` 相当 API から取れるかを確認する。手順詳細は `../design-guardrails/references/consistency-checklist.md` の「3. データ需給表」。作成した対応表は review JSON の `summary` または findings の `message` に根拠として含める（レビュー結果.md への転記はオーケストレーターが担当）。
4.4. **縦串突合検証（必須）**: 画面→operationId→認可→テーブル→シーケンスの一貫性を検証する。`../design-guardrails/references/consistency-checklist.md` の手順に従い、各 operationId について (a)`api/*.yaml` に実在 (b)認可設計に operationId × ロール × テナント条件の行がある (c)CRUD 系はスキーマフィールドが `tables/*.md` のカラムに対応 (d)CRUD 系はシーケンスが存在 (e)認可設計が API description・`権限マトリクス.md` と一致 — を確認する。逆方向（未使用 operationId、`api/*.yaml` に無い認可行）も検出する。不整合は `vertical-trace`／`contract-consistency` の BLOCK として findings に追加する。可能なら決定論スクリプト（`check-vertical-trace.sh`／`check-authorization-coverage.sh`／`check-contract.sh`）と二重化する。
4.45. **画面⇔API 全項目突合（P-12・必須）**: 次を実行し、findings をファイルに保存して format-review-json.sh の --merge-json で取り込む。
   ```bash
   bash .claude/skills/_common/scripts/check-wiring-fields.sh docs/design/ > <STATE_DIR>/round-<N>-wiring-fields.json
   ```
   表示項目だけでなく入力項目→リクエストフィールド方向も対象（registerTenant への項目追加漏れ＝2026-07-02 design-amendment の再発防止）。
   stderr の「not-checked 画面」一覧は aspects TSV に partial として記録し、LLM レビューで手動突合すること。
4.5. 切断チェック（必須）: 次のスクリプトでファイル切断・破損を機械的に検出し、findings JSON を一時ファイルに保存する。
   ```bash
   bash .claude/skills/_common/scripts/check-truncation.sh docs/requirements/ docs/design/
   ```
   - 出力は findings JSON 配列（BLOCK / SUGGEST / NIT の重大度付き、`severity` `path` `line` `category` `message` `suggested_fix` の各フィールドを持つ）。
   - 検出内容: Invalid UTF-8（マルチバイト文字途中切断 = BLOCK）、日本語末尾で句読点なし（SUGGEST）、Markdown テーブル行が `|` で閉じていない（SUGGEST）、末尾近傍で括弧未閉じ（SUGGEST）、末尾改行なし（NIT）。
   - スクリプトの findings JSON は `<STATE_DIR>/round-<N>-check-truncation.json` 等の一時ファイルに保存し、`format-review-json.sh` の `--merge-json` で取り込む（手動マージ禁止）。重複（同一 path × 同一 message）は自動的に片方だけ残る。
4.6. **YAML フォーマットチェック（必須）**: 次のスクリプトで `docs/design/api/` 配下の YAML ファイルの構文・フォーマットを機械的に検出し、findings JSON を一時ファイルに保存する。
   ```bash
   bash .claude/skills/_common/scripts/validate-yaml-format.sh docs/design/api
   ```
   - 出力は findings JSON 配列（`severity` `path` `line` `category` `message` `suggested_fix` の各フィールドを持つ）。
   - YAML 構文エラー（Prettier がパースできない場合）は `BLOCK / openapi` カテゴリ。openapi-typescript での型生成も失敗するため必ず修正が必要。
   - フォーマット違反のみ（内容は正しいが整形規約に違反）は `NIT / style` カテゴリ。
   - スクリプトの findings JSON は `<STATE_DIR>/round-<N>-validate-yaml-format.json` 等の一時ファイルに保存し、`format-review-json.sh` の `--merge-json` で取り込む（手動マージ禁止）。重複（同一 path × 同一 message）は自動的に片方だけ残る。
   - マルチリポジトリ構成でカレントが `claude-poc-rules/` の場合は `docs/design/api` → `claude-poc-docs/docs/design/api` に読み替える。

5. **findings を TSV で出力（JSON 手書き禁止・P-08）**: 自分のレビューで見つけた指摘を
   `<STATE_DIR>/round-<N>-findings.tsv` に 1 行 1 指摘のタブ区切りで Write する
   （列: severity/category/path/line/message/suggested_fix/related_files。message 内の強調は鉤括弧「」を使い、タブ・改行を含めない）。
   決定論スクリプト（check-*.sh）の findings JSON はファイルに保存しておき、手動でマージしない。
6. **検査済み観点リストを TSV で出力（P-10・必須）**: `<STATE_DIR>/round-<N>-aspects.tsv` に、
   本スキルの全レビュー観点カテゴリ + 実行した決定論スクリプトを 1 行ずつ
   （列: aspect/status(checked|partial|not-checked)/method(script|llm|none)/note）記載する。
   全観点を必ず列挙し、見なかった観点は not-checked + 理由を書く（沈黙スキップの禁止）。
7. **review JSON を機械生成**:
   ```bash
   bash .claude/skills/_common/scripts/format-review-json.sh design \
     <STATE_DIR>/round-<N>-findings.tsv \
     <STATE_DIR>/round-<N>-review.json \
     --aspects <STATE_DIR>/round-<N>-aspects.tsv \
     --summary <summaryファイル(任意)> \
     --merge-json <check-*.shのfindings JSONファイル>...
   ```
   生成とスキーマ検証は機械化されているため、JSON の自己修正リトライは不要。TSV 形式エラー（exit 1）の場合のみ該当行を直して再実行する。
8. **標準出力に JSON パスを 1 行で出す**（レビュー結果.md への追記はオーケストレーターが担当するため、本スキルでは行わない）

## レビュー観点

### BLOCK

- `traceability`: 要件 SCR-XXX / UC-XXX / ACT-XXX / BR-XXX / AC-XXX のいずれかが設計書側で**参照されていない**、または存在しない ID を参照
- `completeness`: 画面ファイル不足（画面一覧.md にあるが個別 md がない）、API YAML 不足、テーブル md 不足、**シーケンスファイル不足**（要件で複数コンポーネント間の交互動作が想定される業務に対応する `sequences/*.md` が無い）。とくに **分岐を持つ業務アクティビティ（ACT-XXX）** に対応するシーケンスが 1 件も無い場合は BLOCK
- `openapi`: OpenAPI YAML が 3.1 規格に違反、`info.description` に関連要件/画面が未記載、`_common.yaml` の共通スキーマを `$ref` せず重複定義
- `db`: `DB定義.md` に全体 ER 図がない（Mermaid `erDiagram` が必要）、テーブル md に部分 ER 図がない、外部キー先のテーブルが未定義
- `db-schema-completeness`: `tables/*.md` の各テーブルについて、(1) 主キー（PK）、(2) 全カラムの型、(3) 文字列カラムの桁（VARCHAR(n) 等）／数値精度、(4) nullable（NOT NULL/NULL）、(5) 一意制約（UNIQUE。複合はカラム組み合わせ）、(6) 外部キー（FK）のカラムと参照先カラムの型一致・削除時挙動（CASCADE/RESTRICT 等）、(7) インデックス方針（不要なら「なし」と明記）、(8) 並行制御列の要否（version 列／楽観・悲観の別）— のいずれかが明記されていない場合は BLOCK。「無い場合も『なし』と明記」を必須とする（暗黙の欠落を禁止）。決定論は `check-db-design-consistency.sh` の findings を取り込む
- `db-contract`: `tables/*.md` のカラムと、供給/受領する `api/*.yaml` のスキーマフィールドが、型・文字数（maxLength ↔ VARCHAR 桁）・必須（required ↔ NOT NULL）・enum 値域 で一致しているか。型マッピング不整合（DB `BIGINT` ↔ API `string`、DB `VARCHAR(50)` ↔ API `maxLength: 255`、enum 値集合差）を BLOCK とする。必須/任意・enum の不一致は従来 `db-nullable` の範囲を内包する（`db-nullable` は別名として残置可）
- `screen-transition`: 画面遷移図のノードが SCR-XXX 形式でない、参照画面が存在しない
- `sequence`: `sequences/*.md` で SEQ-XXX 採番が無い／Mermaid `sequenceDiagram` が無い／対応する SCR-XXX・UC-XXX・API operationId のいずれかが 1 件も引用されていない
- `security`: 認証要否・CORS・JWT 取り扱いが API YAML に未記載
- `architecture`: Controller に業務ロジックを書く前提になっている、フロントに業務判定を寄せている等、CLAUDE.md の設計原則に反する記述
- `nonfunc-traceability`: 要件で **要求値として確定した非機能要件**（性能の応答時間・同時接続数、可用性の稼働時間/RTO/RPO、バックアップ頻度、対象ブラウザ/デバイス等）のうち、設計に落ちる性質のもの（DB インデックス方針・ページング・キャッシュ・バッチ設計・対応ブラウザ前提の実装制約など）が設計書のどこにも反映されていない
- `architecture-doc`: `方式設計.md` が **存在しない**、または論理／物理アーキテクチャ・コンポーネント構成・環境別デプロイ構成のいずれも図示されていない（開発環境=devcontainer の記述のみで本番方式が無い場合も BLOCK）
- `security-design`: `セキュリティ設計.md`（認証・認可の正典）が **存在しない**、または JWT ライフサイクル・CORS・パスワードハッシュ・`@PreAuthorize` 規約とテナントフィルタの実装方式が 1 箇所に集約されていない。要件 `権限マトリクス.md` の各行に対応する **認可設計**（API operationId × 必要ロール × テナント条件）が `セキュリティ設計.md` または `認可設計.md` のどちらにも無い場合も BLOCK。**さらに `api/*.yaml` の全 operationId について認可設計に行（operationId × 必要ロール × テナント条件）が網羅されているかを確認し、行が無い operationId があれば BLOCK（public API は public と明記が必要）。テナント越境応答コード（404）と権限不足（403）が統一されているか、`../design-guardrails/references/security-checklist.md` の必須値（JWT 失効方針・BCrypt コスト 12 以上・Clock 経由・ログイン試行ロック保存先の単一化・レート制限・CORS 許可オリジンの確定値）が方針止まりでなく値で記述されているかを確認する（RC-03／RC-05）。**
- `xss`: 要件で自由入力テキストフィールドを「プレーンテキスト」または「リッチHTML」に分類した結果が `セキュリティ設計.md` に記載されていない。または、プレーンテキストと定義されたフィールドに対して `api/*.yaml` の該当スキーマに `pattern: '^[^<>]*$'` が付与されていない（バックエンドの入力拒否バリデーションの根拠が設計書に存在しないことを意味する）
- `batch-design`: 要件 `外部インターフェース一覧.md` にバッチ（EXT）があり `IF定義.md` でバッチ IF が定義されているのに、`バッチ設計.md`（トランザクション単位・再実行・分割・監視連携・失敗時詳細）が無い／「バッチなし」の明示も無い
- `operation-design`: `運用設計.md` が **存在しない**、または `非機能要件.md` の運用・可用性要求値（監視・アラート・バックアップ/リストア手順・稼働時間帯）が設計に落ちていない
- `concurrency`: 状態遷移・先着・上限・二重防止を持つ業務（要件 `業務ルール.md`／`functional/*.md`／`activities/*.md` で言及）に対し、`tables/*.md` に version 列 or 一意制約が無い、または `sequences/*.md` にロック取得順序が描かれていない（非正規化カウンタ単独での上限判定もここで指摘。RC-01） さらに (1) 「一意制約あり」と定義した集約はその一意制約のカラム組み合わせが業務ルール（先着/上限/二重不可）の単位と一致するか、(2) `sequences/*.md` のロック取得順序が複数フローで矛盾なく同一（親→子／ID 昇順 等）か、(3) 楽観/悲観の選択が `業務ルール.md` の競合特性（更新頻度・衝突許容）と整合するか、までを確認する（version 列の有無だけで終わらせない）
- `vertical-trace`: 画面が呼ぶ operationId が、(a)`api/*.yaml` に実在 (b)認可設計に行がある (c)CRUD 系でスキーマフィールドが `tables/*.md` カラムに対応 (d)CRUD 系でシーケンスが存在 — のいずれかを満たさない。全 operationId で (a)(b) は必須、CRUD 系は (c)(d) も必須（RC-02）
- `contract-consistency`: ①画面の参照 operationId が API YAML に実在 ②認可設計の operationId × ロールが API description・`権限マトリクス.md` と一致 ③ErrorResponse/コード値が `_common.yaml` と共通部品設計で一致 ④スキーマ名の重複なし（複数 YAML の同名 `MessageResponse` 等を禁止）⑤通知の宛先粒度（user/tenant）が `tables/*.md` と一致 ⑥JSON 実フィールド名（`code`/`details[].reason` 等）が文書間で一致 — のいずれか不一致なら BLOCK（RC-02）
- `data-sufficiency`: 画面設計（`screens/SCR-*.md`）で「表示する」と定義された**全データ項目**および業務判定に使う値（自他判定・権限判定用の ID 等）について、供給元 API（operationId × レスポンスフィールド）が存在しない、または画面 md の API 欄に取得経路が明示されていない。とくにログイン直後の画面・共通レイアウト（ヘッダー等）の表示項目が `LoginResponse` または `/me` 相当 API から取得できない場合は BLOCK（2026-06-12 の核心）。**入力項目→リクエストボディのフィールド対応も含む（表示方向だけでなく送信方向も）**（P-12）
- `param-source`: API のパス変数・クエリパラメータについて、その値の出所（前画面のどの項目・どのレスポンスフィールドか）が画面遷移・シーケンスのどこにも現れない
- `status-operation`: 状態遷移（ST-XXX）のガード条件（「成約後は編集不可」等の BR-XXX）が、対応する画面（操作の活性/非活性）と API（4xx 応答）のどちらにも反映されていない
- `error-response`: ErrorResponse／エラーコード体系が `_common.yaml` の `components/schemas/ErrorResponse` に一元定義されていない（各 `api/*.yaml` に個別定義されている）、または `共通部品設計.md`・方式設計でエラーコード体系・例外クラス名・通知宛先が再定義されて `_common.yaml`／`コード値定義` と二重管理になっている（RC-06）
- `db-nullable`: 要件 `functional/*.md` の AC で「必須入力」とされた項目に対応するテーブルカラムが nullable（`NOT NULL` でない）、または「任意」項目が `NOT NULL` になっている。API YAML の `required`/enum/minimum とテーブルカラムの整合（必須/任意・enum 値）も確認し不一致なら BLOCK（RC-11）
- `legend`: 設計書側で **新規に導入した ID または略号**（SEQ-XXX、API 操作 ID、ER 関連名コード、ステータスコード略号など）について、当該ドキュメント冒頭に凡例が存在しない、または凡例から漏れている。CLAUDE.md「略号には凡例を明記」ルール違反
- `open_question_blocker`: `docs/requirements/オープン課題.md` に「設計着手前クローズ必須」区分（Q-NF\* のセキュリティ/ブラウザ/運用系、Q-DM\*、Q-EI\*、Q-MIG\*）で `state == open` のまま残っている Q-ID があり、かつ設計書本体（`非機能要件.md`・`データモデル.md`・`外部インターフェース一覧.md`・`移行要件.md`）の対応箇所が TBD または空欄のまま設計書に取り込まれている。`/design-pre-research` で先にクローズしてから設計を再実行すること
- `quickstart_missing`: `docs/design/quickstart.md` が**存在しない**。`design-from-requirements` の成果物として必須（SC-XXX / AC-XXX と対応づけたエンドツーエンド動作確認ガイド）

### SUGGEST

- `naming`: 同一概念に複数の英語名が混在
- `redundancy`: 同じスキーマが複数 YAML で重複
- `validation`: バリデーション条件が要件と設計で微妙にズレ
- `testability`: test-strategy / scenario-strategy のシナリオ粒度が粗い
- `performance`: N+1 リスクが残るリレーション、欠落しているインデックス
- `common-component`: `共通部品設計.md`（BE）が無い、または共通例外ハンドラ・バリデーション共通化・共通レスポンス整形・ロギング方式が未定義（ErrorResponse スキーマの実装方式が API YAML 側にしか無い）
- `common-layout`: `screens/共通レイアウト.md` が無い、または共通シェル（ヘッダー/ナビ等）の構成要素にデータ源（operationId.フィールド）が明示されていない。各画面 md に「所属レイアウト」の記載が無い画面がある（共通項目が画面ごとに重複定義されている場合もここで指摘）
- `fe-common-component`: `フロントエンド共通設計.md` が無い、または共通 UI コンポーネント・API クライアント・ErrorResponse.code → 表示文言（MSG-XXX）マッピング・認可ガードのいずれかが未定義。または界面契約（ErrorResponse/コード値）・技術スタックを再定義している（`_common.yaml`／`コード値定義`／`claude-poc-frontend/.claude/rules/` と二重管理）
- `nonfunc-test`: `非機能テスト計画.md` が無い／非機能要求値に対する検証方法の対応表が無い。または `セキュリティテスト観点.md`（認可バイパス・テナント越境・JWT 改ざん・機微情報漏えい等）が無い
- `message-trace`: 設計の ErrorResponse コード・通知/メール文面が、要件 `メッセージ一覧.md`（MSG-XXX）・`コード値定義.md`・`通知・文面定義.md` と相互参照されていない（コード値 enum と `_common.yaml` の対応含む）
- `sequence`: SEQ-XXX 採番済みだが例外フロー・代替フローの記述が不足、または対応する AC-XXX 引用が一部欠落
- `code-value-chain`: コード値（enum）が `コード値定義.md`（要件）→ `_common.yaml`（設計）の 2 層で値・表示名が一致しない、または設計で新設された enum が `コード値定義.md` に未掲載（RC-06）
- `authz-screen`: `権限マトリクス.md` で「不可」とされた操作が、画面設計上で非表示/非活性として扱われていない（防御の正典は API 側だが、画面設計に表れない場合は指摘）
- `validation-pair`: 画面 md のバリデーション（文字数・必須）と API YAML の制約（maxLength・required）が不一致
- `legend`: 要件定義で定義済みの ID（`SCR-XXX` / `UC-XXX` / `ACT-XXX` / `AC-XXX` / `BR-XXX` 等）を引用しているが、出典への参照（リンク／パス）が無い

### NIT

- `style`: YAML/MD のインデント揺れ、末尾空白

## 出力 JSON スキーマ

JSON の **構造**（`severity` `path` `line` `category` `message` `suggested_fix` `related_files` フィールドと配列形式）は review-requirements と同じ。`related_files` には指摘の整合確認に必要な関連ファイル（`path` 以外）を記載する。ただし `phase: "design"` とし、`category` には **本ファイルで定義した design 専用カテゴリ（上記 BLOCK / SUGGEST / NIT の一覧）** を使う（review-requirements の要件カテゴリ enum は流用しない・M-4）。

利用可能なカテゴリ一覧（`category` フィールドの許容値）:
`traceability | completeness | openapi | db | screen-transition | sequence | security | architecture | nonfunc-traceability | architecture-doc | security-design | xss | batch-design | operation-design | legend | open_question_blocker | quickstart_missing | naming | redundancy | validation | testability | performance | common-component | nonfunc-test | message-trace | style`

このうち `record-review.sh` が **重要カテゴリ（IMPORTANT）** として SUGGEST 件数閾値（既定 0）で素通りを防ぐのは次で、表記は `record-review.sh` の IMPORTANT 集合と一字一句一致させること: `contract-consistency` / `error-response` / `security-design` / `authz-screen` / `concurrency` / `data-sufficiency` / `db-schema-completeness` / `db-contract`。（これらを SUGGEST で出す場合も IMPORTANT 判定が効くよう、上記の正規表記を厳守する。`vertical-trace` 等は BLOCK 区分のため別途必ずブロックされる。）

`checked_aspects` / `uncovered_areas`（P-10）: `format-review-json.sh` が aspects TSV から生成するフィールド。`checked_aspects` は検査した観点の一覧（aspect/status/method/note）、`uncovered_areas` は status が `checked` 以外だった観点（未検査・部分検査とその理由）の一覧。**PASS はこのリストが揃って初めて解釈可能** であり、findings が 0 件でも `uncovered_areas` に重要観点が残っていれば「検査していないだけ」の可能性がある。採択者は `uncovered_areas` を見て残リスクを判断する。

## 注意事項

- このスキルでファイルを書き換えない。
- 要件側に問題がある場合（要件定義が完全でない等）は BLOCK ではなく SUGGEST にし、message に「要件定義 phase へのフィードバックが必要」と明記。
- `message` / `title` / `recommendation` などの自然言語フィールドで語句を強調する場合は、ASCII の `"..."` ではなく **鉤括弧 `「...」`** を使う。JSON 文字列内の `"` エスケープ漏れ事故を減らすため（過去発生事例あり）。
