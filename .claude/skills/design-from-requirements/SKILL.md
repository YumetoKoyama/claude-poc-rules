---
name: design-from-requirements
description: 採択済みの要件定義書（docs/requirements/）から、React フロントエンドと Spring Boot REST API バックエンドを前提にした実装可能な設計書を作成するときに使う。これは設計成果物の作成専用であり、後続の製造やテストには進まない。
context: fork
argument-hint: [要件定義ディレクトリのパス（省略時は docs/requirements/）]
---

# 要件定義書から設計書を作成する

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

この skill の入力は **採択済みの要件定義書** です。要件定義書がない場合、または採択済みでない場合は中断し、先に `requirements-from-input` の実行とレビュー採択を依頼すること。

> **採択ゲート（必須）**: 採択は「要件定義書の PR を人間がレビューし docs リポジトリの `main` へマージすること」で行う（branch protection で直 push 禁止が前提）。開始前に、入力の要件定義書（`docs/requirements/`）が `main` に存在することを確認する（CI は main 契機のため自明。ローカルでは `git log origin/main -- docs/requirements/` 等で確認し、未マージなら中断して人手レビュー・マージを依頼する）。採択は AI の自己判断では行わず、Claude 自身がマージして採択扱いにしてはならない。

> **スタック確定ゲート（必須）**: 採択ゲートの確認後、`bash .claude/skills/_common/scripts/check-stack-decided.sh` を実行する。exit 1（`要確定` の残存、または確定表 `*-00-stack.md` の不存在）の場合は設計を**開始せず**、スクリプトが出力した未確定項目の一覧をそのまま人間に提示して中断する。Claude が既定値で補完して続行してはならない（CLAUDE.md「技術スタックの正典と確定ルール」）。確定の記入は人間が `claude-poc-frontend/.claude/rules/frontend-00-stack.md`・`claude-poc-backend/.claude/rules/backend-00-stack.md` に対して行う。

> **ガードレール適用（必須）**: 設計成果物の作成・補完の全工程で `design-guardrails` スキルの **MUST NOT（設計アンチパターン）と縦串整合・セキュリティチェックリスト** を適用する（S11）。詳細は `../design-guardrails/references/negative-patterns.md`（Controller 肥大化・N+1 設計・ErrorResponse 分散・認可を FE に寄せる 等）、`../design-guardrails/references/consistency-checklist.md`（画面→operationId→認可→テーブル→シーケンスの縦串＋データ需給表）、`../design-guardrails/references/security-checklist.md`（セキュリティ設計の必須項目）を参照する。

要件定義入力: $ARGUMENTS（省略時は `docs/requirements/` 配下を全件対象）

## 成果物

設計書は 1 ファイルにまとめず、以下のファイルに分けて出力する。

- `docs/design/概要.md` — スコープ要約・前提条件・ユースケース・リスク（要件定義をもとに要約）
- `docs/design/screens/[画面名].md` — 画面設計（**画面ごとに 1 ファイル**、`SCR-XXX-画面名.md` 形式の日本語名、ファイル冒頭に画面 ID を記載）
- `docs/design/screens/画面遷移.md` — 画面遷移図（Mermaid、画面 ID 表記）
- `docs/design/screens/共通レイアウト.md` — 全画面共通のアプリシェル（ヘッダー／フッター／グローバルナビ／サイドバー）の構成・表示項目とデータ源・挙動・適用範囲（各画面の「所属レイアウト」欄から参照）
- `docs/design/sequences/[シーケンス名].md` — シーケンス設計（**主要シーケンスごとに 1 ファイル**、`応募確定.md` 等の業務用語の日本語名、SEQ-XXX 採番、Mermaid `sequenceDiagram`、対応する SCR/UC/ACT/API/AC を明示）
- `docs/design/api/_common.yaml` — API 共通スキーマ（OpenAPI 3.1 components）
- `docs/design/api/[リソース名].yaml` — API 設計（**リソースごとに 1 ファイル**、1 ファイル内に同リソースの全 HTTP メソッドを集約、OpenAPI 3.1 準拠 YAML、kebab-case 英語）
- `docs/design/IF定義.md` — IF 定義（外部・内部インターフェース）
- `docs/design/DB定義.md` — DB 全体方針（全体 ER 図含む / Mermaid `erDiagram`）
- `docs/design/tables/[テーブル名].md` — テーブル定義（**テーブルごとに 1 ファイル**、DB 物理名と同じ snake_case 英語、部分 ER 図含む / Mermaid `erDiagram`）
- `docs/design/方式設計.md` — 論理／物理アーキテクチャ・コンポーネント構成・環境別デプロイ構成・ミドルウェア構成（Mermaid、本番方式が対象）
- `docs/design/セキュリティ設計.md` — 認証・認可の正典（JWT / CORS / パスワードハッシュ / ログイン試行制御 / `@PreAuthorize` 規約・テナントフィルタ）。認可設計を内包または分割
- `docs/design/認可設計.md` — API operationId × 必要ロール × テナント条件（要件 `権限マトリクス.md` の物理化。`セキュリティ設計.md` に統合しても可）
- `docs/design/バッチ設計.md` — バッチごとのトランザクション単位・再実行・分割・監視連携・失敗時詳細（`IF定義.md` の IF 粒度を詳細化。「バッチなし」の場合もその旨を明記）
- `docs/design/共通部品設計.md` — 共通例外ハンドラ / バリデーション共通化 / 共通レスポンス整形 / ロギング方式（ErrorResponse の実装方式を含む）。**BE（Spring Boot）側の横断関心事**
- `docs/design/フロントエンド共通設計.md` — **FE（React）側の横断関心事**: 共通 UI コンポーネント・API クライアント・ErrorResponse.code → 表示文言（MSG-XXX）マッピング・共通バリデーション・認可ガード・状態管理方針（技術スタックは `claude-poc-frontend/.claude/rules/` を参照し再掲しない）
- `docs/design/運用設計.md` — 監視・アラート・バックアップ/リストア手順・ジョブ運用・ログ保持/監査ログ出力箇所（`非機能要件.md` の運用・可用性要求値を反映）
- `docs/design/テスト戦略.md` — 単体テスト方針
- `docs/design/シナリオ戦略.md` — E2E シナリオ方針
- `docs/design/非機能テスト計画.md` — 性能・負荷・可用性の検証計画（非機能要求値ごとに検証方法・目標値・シナリオを対応づけ）
- `docs/design/セキュリティテスト観点.md` — 脆弱性観点（認可バイパス・テナント越境・JWT 改ざん・機微情報漏えい等）。テストデータ設計・全体テスト計画を含めてよい（任意・推奨）
- `docs/design/quickstart.md` — エンドツーエンド動作確認ガイド（前提・セットアップ手順・機能ごとの検証シナリオ・期待結果。SC-XXX / AC-XXX と対応づける）

**ID 凡例の共通化（P-14/C-2）**: ID 凡例表を各成果物 md に再掲しない。初回に `.claude/skills/_common/references/id-legend.md` を docs リポジトリの `docs/凡例.md` へコピーし、各成果物は冒頭に「ID 凡例: [docs/凡例.md](相対パス) 参照」の 1 行のみ置く。新規 ID 体系を導入する場合は凡例への追記案を提示し人手で反映する。

## 指示

0. **Constitution ロード（任意）**: 設計を開始する前に `docs/architecture/constitution.md` が存在するか確認する。存在する場合は Read してプロジェクト設計原則を把握し、Constitution Check ゲートの全項目を確認する。❌ が残る場合は「複雑さの正当化」表に記録した上で設計に進む（黙って無視しない）。ファイルが存在しない場合はスキップする。

1. `docs/requirements/概要.md` を最初に読み、スコープと前提を把握する。
2. `docs/requirements/画面一覧.md` の画面 ID（SCR-XXX）一覧を読み、すべての画面について `docs/design/screens/[画面名].md` を作成する。
3. 画面設計ファイルの冒頭には **画面 ID** と **画面名** を見出しに明記する（例: `# 画面設計: SCR-001 ログイン画面`）。
3.5. 各画面設計ファイルに **`## 受け入れ条件`** セクションを必ず作成し、対応する `docs/requirements/functional/[機能名].md` の AC-XXX を **Given/When/Then 形式のまま** 引き継ぐ。要約・圧縮禁止。正常系・異常系・境界値・権限境界の 4 区分すべてを含める。各行に `operationId` 列を設け、テストコードから直接参照できる粒度にする。AC-XXX が未定義の画面は画面概要から観点を抽出して AC を採番する。
   - **出力形式は必ず 7 列の Markdown テーブル**（`| AC-ID | 区分 | Given（前提状態） | When（操作） | Then（期待結果） | 関連 BR | operationId |`）とする。箇条書き（`* Given: ...` / `* When: ...` / `* Then: ...`）やリスト形式での出力は禁止。テンプレートは `references/overview-screens.md` の「受け入れ条件」セクションを厳守する。
4. 画面遷移は `docs/design/screens/画面遷移.md` に Mermaid（`flowchart` 推奨）で必ず描く。ノードは画面 ID を使う。
4.5. **主要なシーケンス**（複数コンポーネント間の交互動作が発生する業務、応募確定・合意成約・運送ステータス確定・評価完了 等）について、`docs/design/sequences/[シーケンス名].md` を 1 シーケンス 1 ファイルで作成する。ファイル名は業務用語の日本語名（例: `応募確定.md`）。各ファイルで SEQ-XXX を採番し、Mermaid `sequenceDiagram` でフロントエンド ↔ API ↔ DB（必要に応じて外部システム）の交互動作を描く。対応する画面（SCR-XXX）・ユースケース（UC-XXX）・業務フロー（ACT-XXX）・API（operationId）・受け入れ条件（AC-XXX）を必ず引用する。
   - **対象の拡大（必須）**: 業務フローに加えて、横断機能である **認証（ログイン → 初期画面／共通ヘッダーのデータ取得経路）・通知（発火 → 表示）** のシーケンスを必ず含める。ログインシーケンスでは「ログイン後に共通レイアウト（ヘッダー等）へ表示するデータの取得経路（`LoginResponse` または `/me` 相当 API）」を明示する。
   - **例外フローの明示（ADD-1）**: 各シーケンスには正常フローに加えて、主要な例外フローを `alt`／`opt` フラグメントで含める（認可失敗 → 403、バリデーションエラー → 400、状態競合・二重・DB 制約違反 → 409 Conflict、外部システムタイムアウト → 504 等）。例外が多い場合は別ファイルに分割してよい（例: `応募確定_例外.md`）。
4.6. **共通レイアウト設計（必須）**: 全画面共通のアプリシェル（ヘッダー／フッター／グローバルナビ／サイドバー）を `docs/design/screens/共通レイアウト.md` に 1 枚で設計する。構成要素ごとに表示項目・**データ源（operationId.フィールド）**・表示条件（ロール）・挙動を記述し、共通シェルに乗る画面と認証前独立レイアウトの画面を区分する。各画面 md には「所属レイアウト」を明記し、共通シェルの場合は差分のみ記述する（共通項目を画面ごとに重複させない）。
4.7. **画面データ源マッピング（必須）**: 各画面 md の「出力・表示内容」表に **データ源列（operationId.フィールド）** を必須化する。画面で「表示する」と定義した全項目および業務判定に使う値（自他判定・権限判定用の ID 等）について、供給元 API（operationId × レスポンスフィールド）を特定する。供給元が未設計の項目を発見した場合は、その場で API 設計（レスポンス追加または `/me`・`LoginResponse` 等の新設）に反映してから次の画面に進む（断絶を後工程に持ち越さない）。詳細は `../design-guardrails/references/consistency-checklist.md` のデータ需給表手順を参照。
5. API は **OpenAPI 3.1 準拠の YAML** でリソースごとに 1 ファイルを作成する（`docs/design/api/[リソース名].yaml`）。同じリソースに属する複数の HTTP メソッド・パスは同一ファイル内の `paths:` 配下にまとめる。各 operationId には `x-ac` 拡張フィールドで対応する AC-ID を列挙する（例: `x-ac: [AC-001, AC-101, AC-201]`）。これによりテストジェネレーターからのトレーサビリティを確保する。
6. API 横断で使うスキーマ（共通エラー、ページング、認証ヘッダ等）は `docs/design/api/_common.yaml` の `components` 配下に定義し、各 YAML から `$ref` で参照する。**ErrorResponse スキーマ（HTTP ステータス × エラーコード × メッセージの対応）とエラーコード enum、例外クラス名、通知宛先粒度（user/tenant）は `_common.yaml`・`コード値定義` を唯一の正典とし、各 `api/*.yaml`・共通部品設計・方式設計で個別定義・再定義しない（`$ref`・参照のみ）。`共通部品設計.md` は実装方式（例外ハンドラのマッピングロジック・例外クラス → HTTP ステータス対応）のみを記述する。同名スキーマ（`MessageResponse` 等）を複数 YAML で別定義しない（RC-06／RC-02）。**
6.1. **YAML セルフチェック（必須・生成直後ガードレール）**: ステップ 5–6 で生成した全 YAML ファイルに対し、以下の 3 スクリプトを順に実行して機械的な品質を検証する。YAML の構文・$ref・契約整合を後工程（DB 設計・セキュリティ設計等）に持ち越さない。
```bash
   bash .claude/skills/_common/scripts/check-openapi-valid.sh docs/design/api/        # OpenAPI 3.1 構文＋$ref 参照先存在
   bash .claude/skills/_common/scripts/check-contract.sh docs/design/                  # operationId/ErrorResponse/コード値 の文書間突合
   bash .claude/skills/_common/scripts/validate-yaml-format.sh docs/design/api         # Prettier フォーマット検証
```
   - マルチリポジトリ構成でカレントが `claude-poc-rules/` の場合は `docs/design/api` → `claude-poc-docs/docs/design/api`、`docs/design/` → `claude-poc-docs/docs/design/` に読み替える。
   - **失敗時の自己修正**: いずれかのスクリプトが exit 1 を返した場合、エラー出力の指摘箇所を修正し、**3 スクリプトすべてが exit 0 になるまで再実行する**（最大 3 回）。3 回で解消しない場合はエラー内容をそのまま `docs/design/概要.md` の「前提と未解決事項」に記録し、review に引き継ぐ（ただし構文エラー・$ref 破損が残る場合は後続ステップに進まない）。
   - `validate-yaml-format.sh` の NIT（フォーマット違反のみ）は `npx prettier --write` で自動修正してよい。
   - このステップは review の決定論検証（4.2/4.6）と同じスクリプトを再利用しており、レビューでの YAML 関連 BLOCK/NIT を生成段階で排除する。
   - `check-contract.sh` の認可設計チェック（認可設計は 9.2 で後に作成）は WARN 出力のみで exit 0 となるため、この時点での実行に支障はない。
7. DB 全体方針は `docs/design/DB定義.md` に書き、必ず Mermaid の `erDiagram` を使った **全体 ER 図** を含める。
8. テーブルごとの詳細は `docs/design/tables/[テーブル名].md` に分割し、各ファイルの末尾に **そのテーブルとリレーションのある周辺テーブルを含めた部分 ER 図** を Mermaid `erDiagram` で必ず描く。
8.1. **必須/任意・enum 整合（RC-11）**: テーブルカラムの NULL 制約・API の required/enum/minimum を要件の入力必須/任意・enum と整合させる。`functional/*.md` の AC で「必須入力」とされた項目に対応するカラムは `NOT NULL`・API は `required`、「任意」は nullable・optional とする。enum は `コード値定義.md` → `_common.yaml` で値・表示名を一致させる（`desired_amount`／`truck_type`／`volume_m3` 等の不一致を作らない）。
8.6. **並行制御の設計（RC-01）**: 状態遷移・カウンタ・先着・上限・二重防止を持つ集約には、`tables/*.md` に version 列（楽観 `@Version` 用）の要否と一意制約を明記し、`sequences/*.md` に **ロック取得順序**（どのテーブルをいつ `FOR UPDATE` で掴むか、セット連動の巻き込みロック含む）を図示する。先着・上限・二重不可はアプリ層の read-modify-write ではなく **DB 一意制約／条件付き UPDATE／行ロック** で保証し、非正規化カウンタ単独での上限判定はしない。詳細は `../design-guardrails/references/negative-patterns.md` のカテゴリ B を参照。
8.7. **テーブル定義の完全性 + tables↔api 整合（BE↔DB 対称化）**: 各 `tables/*.md` に、(1) 主キー（PK）、(2) 全カラムの型、(3) 文字列カラムの桁（VARCHAR(n) 等）／数値精度、(4) NULL/NOT NULL、(5) 一意制約（複合はカラム組み合わせ）、(6) 外部キー（FK）の参照先カラム型一致・削除時挙動（CASCADE/RESTRICT 等）、(7) インデックス方針、(8) 並行制御列（version）の要否 — を**すべて明記**する。該当が無い項目も **「なし」と明記**する（暗黙の欠落を禁止）。さらにカラムの型・桁・必須・enum を、供給/受領する `api/*.yaml`（maxLength／required／enum）と一致させる（DB `VARCHAR(50)` ↔ API `maxLength: 50` 等）。レビューの `db-schema-completeness`／`db-contract`（`check-db-design-consistency.sh`）に対応する produce 側規約。詳細は `../design-guardrails/references/negative-patterns.md` の B-4〜B-6・`consistency-checklist.md` の §8 を参照。
9. IF 定義・テスト方針・シナリオ方針はカテゴリごとに 1 ファイルで出力する。
9.1. **方式設計** を `方式設計.md` に作成し、論理／物理アーキテクチャ・コンポーネント構成・環境別デプロイ構成を Mermaid で図示する（開発環境ではなく本番方式が対象）。
9.2. **セキュリティ設計** を `セキュリティ設計.md` に作成し、認証・認可を 1 箇所に集約する（JWT ライフサイクル・CORS・パスワードハッシュ・`@PreAuthorize` 規約・テナントフィルタ）。要件 `権限マトリクス.md` の各行に対応する **認可設計**（operationId × ロール × テナント条件）を内包するか `認可設計.md` に分割する。
   - **セキュリティ必須値の確定（RC-05、`../design-guardrails/references/security-checklist.md` を必ず適用）**: JWT 失効方針（STATELESS なら logout はクライアント破棄と明記／失効が要るならブラックリスト設計）、アクセス/リフレッシュトークン有効期限、ログイン試行ロックの **保存先を 1 つに確定**（DB か Redis）、ユーザー列挙防止（400 はメール形式エラーのみ）、BCrypt コスト（12 以上）、時刻は Clock 経由、パスワードリセットのレート制限とメール送信のトランザクション外実行、CORS 許可オリジンの確定値を **方針ではなく値** で記述する。
   - **認可の網羅と越境応答コードの統一（RC-03/RC-05）**: `api/*.yaml` の全 operationId が認可設計に行を持つ（public は public と明記）。**テナント越境は 404、自テナント内の権限不足は 403** に統一する。テナントフィルタは SELECT だけでなく UPDATE/DELETE/COUNT/集計クエリにも適用する設計とする。認可は `@PreAuthorize` に集約し UseCase 内の手書きロールチェックと二重管理しない。
9.3. 要件 `外部インターフェース一覧.md` にバッチ（EXT）がある場合は **バッチ設計** を `バッチ設計.md` に作成する（トランザクション単位・再実行・分割・監視連携・失敗時詳細）。バッチが無ければその旨を明記。横断的関心事は **共通部品設計**（`共通部品設計.md`：例外ハンドラ・バリデーション共通化・ロギング方式・ErrorResponse の実装方式）に集約する。
9.4. **運用設計** を `運用設計.md` に作成し、`非機能要件.md` の運用・可用性要求値（監視・バックアップ・稼働時間帯）を設計に落とす。テスト計画として **非機能テスト計画**（`非機能テスト計画.md`：非機能要求値 → 検証方法の対応表）と **セキュリティテスト観点**（`セキュリティテスト観点.md`）を作成する。
9.5. **quickstart.md** を `docs/design/quickstart.md` に作成する。`functional/[機能名].md` の成功基準（SC-XXX）と受け入れ条件（AC-XXX）を検証シナリオとして対応づけ、以下の構成で記述する。**AC の内容は `functional/` から Given/When/Then のまま引き継ぐこと。一行要約への圧縮禁止**（例: `AC-001（要約）` ではなく Given/When/Then の各列を明記する）。
   - **前提条件**: 検証実施に必要な環境・データ・権限
   - **セットアップ手順**: ローカル/CI でアプリを起動するコマンド列（実際に動くコマンドを記載、フレームワーク固有コマンドでよい）
   - **機能別検証シナリオ**: 機能名・対応 SC-XXX / AC-XXX・実行手順・期待結果
   - **制限事項**: 自動化不可の手動確認項目
   quickstart.md は実装完了後の動作確認で使い、`tasks-from-design` で生成するタスクの受け入れ根拠ともなる。実装コード（クラス本体・マイグレーション全文等）は書かない。
9.5. 設計の ErrorResponse コード・通知/メール文面は、要件 `メッセージ一覧.md`（MSG-XXX）・`コード値定義.md`・`通知・文面定義.md` と相互参照する。**ErrorResponse・例外クラス名・コード値 enum・通知宛先粒度（user/tenant）は `_common.yaml` と `コード値定義` を唯一の正典とし、共通部品設計／方式設計／各 YAML は再定義せず `$ref`・参照のみとする（`_common.yaml` の enum はコード値定義の物理化として値・表示名を一致させる）。JSON 上の実フィールド名（`code`／`details[].reason` 等）を文書間で一字一句一致させる（RC-06／RC-02）。**
9.6. **フロントエンド共通設計** を `フロントエンド共通設計.md` に作成し、FE 横断の共通部品（共通 UI コンポーネント・API クライアント・**ErrorResponse.code → 表示文言（MSG-XXX）のマッピング**・共通バリデーション・ルーティング/認可ガード・状態管理方針）を設計する。界面契約（`_common.yaml` の ErrorResponse・コード値）と要件 `メッセージ一覧.md`／`コード値定義.md` を正典として対応づけ、コード体系・文言・技術スタックを再定義しない（スタックは `claude-poc-frontend/.claude/rules/` を参照）。`共通部品設計.md` は BE、本ファイルは FE と責務を分ける。
10. 固定ファイル名（概要.md, IF定義.md 等）は日本語名で統一する。可変部の命名は次のとおり: 画面名は `SCR-XXX-画面名.md` 形式の日本語名（例: `SCR-001-ログイン.md`）、API はリソース名の kebab-case 英語（例: `jobs.yaml`, `users.yaml`, `applications.yaml`）、テーブル名は DB 物理名と同じ snake_case 英語（例: `users.md`）。
11. 既にファイルが存在する場合は該当ファイルのみ更新し、無関係なファイルは書き換えない。
12. 各ファイルの構造には [design-spec-template.md](design-spec-template.md) を使う。
13. バックエンド、フロントエンド、DB、UT、E2E が独立して着手できる粒度まで具体化する。
14. 要件定義に存在しない仕様を勝手に補完しない。不明点は `docs/design/概要.md` の「前提と未解決事項」節に列挙し、設計を確定させない箇所として明示する。
15. この skill の責務は設計成果物の作成までとし、実装、UT、カバレッジ改善、静的解析、E2E の実行やファイル作成には進まない。
15.1. **テンプレートに定義されていないセクションを追加しない**。画面設計ファイルのセクション構成は `references/overview-screens.md` の `screens/[画面名].md` テンプレートに定義されたもののみとする。特に **ワイヤーフレーム（罫線・ボックス描画によるレイアウト図）は生成禁止**（セクション名を問わない。「画面構成」「画面レイアウト（概略）」等の名称でも不可）。UI の視覚的表現は後続の UI 設計工程（Claude Design）で行う。
16. 最後に、人手レビューと採択後に後続 skill を起動する必要があることを明記する。

## 完了条件

- `docs/design/` 以下に上記のファイル構成で設計成果物が出力されている。
- 画面ごとに個別ファイルが作成され、画面 ID が明記されている。
- `docs/design/screens/画面遷移.md` に Mermaid 画面遷移図が存在する。
- `screens/共通レイアウト.md` が作成され、共通シェルの構成要素ごとにデータ源（operationId.フィールド）が明示され、各画面 md に「所属レイアウト」が記載されている（共通項目の画面別重複が無い）。
- `docs/design/sequences/` 配下に主要シーケンスごとの `[シーケンス名].md` が作成され、SEQ-XXX が採番され、対応する SCR/UC/ACT/API/AC が引用されている。
- YAML セルフチェック（`check-openapi-valid.sh`・`check-contract.sh`・`validate-yaml-format.sh`）がステップ 6.1 で exit 0 を通過している（または 3 回試行後の未解消エラーが「前提と未解決事項」に記録されている）。
- API は OpenAPI 3.1 YAML としてリソース単位に分割されており（1 ファイルに同リソースの全メソッドを集約）、共通スキーマは `_common.yaml` に集約されている。
- DB は `DB定義.md`（全体 ER 図）と `tables/[テーブル名].md`（部分 ER 図）の構成で出力されている。
- `方式設計.md` `セキュリティ設計.md`（認可設計を内包または `認可設計.md` 分割）が作成され、要件 `権限マトリクス.md` の各行が認可設計に対応している。
- バッチがある場合 `バッチ設計.md`、横断関心事 `共通部品設計.md`（BE）・`フロントエンド共通設計.md`（FE）、`運用設計.md` が作成され、非機能要件の運用・可用性要求値が反映されている。
- `フロントエンド共通設計.md` に 共通 UI コンポーネント・API クライアント・ErrorResponse.code → 表示文言（MSG-XXX）マッピング・認可ガードが定義され、界面契約・コード値・技術スタックを再定義していない。
- `非機能テスト計画.md`（非機能要求値 → 検証方法の対応表）と `セキュリティテスト観点.md` が作成されている。
- `quickstart.md` が作成されており、SC-XXX / AC-XXX を検証シナリオとして対応づけた機能別の動作確認手順が含まれている。
- `docs/architecture/constitution.md` が存在する場合、Constitution Check ゲートの確認結果が `概要.md` の「前提条件と未解決事項」に記録されている。
- 各画面 md の表示項目表に **データ源列（operationId.フィールド）** があり、供給元の無い表示項目・業務判定用 ID が残っていない（データ需給の断絶なし）。
- 状態遷移・先着・上限を持つ集約に version 列 or 一意制約があり、シーケンスにロック取得順序が描かれている。
- 各 `tables/*.md` に PK・型・桁・NULL・一意制約・FK 型・インデックス方針・version 要否がすべて明記され（不要は「なし」と明記）、型・桁・enum が `api/*.yaml` と一致している（db-schema-completeness／db-contract）。
- ErrorResponse・コード値・例外クラス名・通知宛先が `_common.yaml`／`コード値定義` に一元化され、各 YAML・共通部品設計で再定義されていない。
- 全 operationId が認可設計に行を持ち、テナント越境応答コード（404）と権限不足（403）が統一されている。
- `概要.md` に前提、未解決事項、レビュー観点が明記されている。
- 後続工程は未着手であり、人手レビュー待ちであることが明記されている。

## 追加資料

- テンプレート: [design-spec-template.md](design-spec-template.md)
