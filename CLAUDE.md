# Web アプリ開発ガイダンス（React / Spring Boot）

このリポジトリは、フロントエンドを TypeScript（React）、バックエンドを Java（Spring Boot）で構成する Web アプリケーションを Claude Code で設計・実装・検証するための共通設定を提供します。

## 開発フロー（skill オーケストレーション）

本プロジェクトは **skill だけでオーケストレーション** する。各フェーズに **`*-loop` orchestrator skill** があり、`produce → review → fix → review` を最大 3 回まで自動で回す（Pattern 4: Iterative Loop）。設計の根拠は [docs/architecture/skill-orchestration.md](docs/architecture/skill-orchestration.md)。

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
      fix    : /fix-requirements が BLOCK + SUGGEST を反映（NIT は無視）
      → BLOCK == 0 または 3 回反復で終了

2. 人手レビュー（要件定義の採択）
   └─ 採択前は設計・製造・テスト・Issue 起票のいずれにも進まない

3. /design-loop [docs/requirements/]
   └─ produce: /design-from-requirements が docs/design/ を生成
        ├─ 概要.md / screens/画面遷移.md / screens/[scr-id]-*.md
        ├─ api/_common.yaml / api/[リソース名].yaml（OpenAPI 3.1、リソースごとに 1 ファイル）
        ├─ IF定義.md / DB定義.md / tables/[テーブル名].md
        ├─ 方式設計.md / セキュリティ設計.md(認可設計を内包or分割) / バッチ設計.md / 共通部品設計.md / 運用設計.md
        └─ テスト戦略.md / シナリオ戦略.md / 非機能テスト計画.md / セキュリティテスト観点.md
      review : /review-design
      fix    : /fix-design
      ※ 単体テストマトリクス(TC)・トレーサビリティマトリクス(RTM) は製造フェーズで作成（/test-design-from-issue）。結合テストマトリクス(IT) は製造から分離した結合テスト工程（/integration-test-from-design）で設計・実施する

4. 人手レビュー（設計書の採択）
   └─ 採択前は製造・テスト・Issue 起票のいずれにも進まない

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

7. /create-issues-from-design [docs/design/]
   └─ 設計書 + ui-design/handoff/README.md の scr-id→prototype 関数マッピングを解析し、
      GitHub Issue を画面・API・IF・テーブル単位で起票（画面 Issue には prototype 参照を埋め込む）

8. /implement-loop <ISSUE-NUMBER>
   └─ produce: /implement-from-issue が実装・品質ゲート（UT / 静的解析 を Pattern 2 で並列）・テスト設計（単体マトリクス＋RTM を 2 タッチ＝実装と並行ドラフト→実装後に実コード整合で確定。/test-design-from-issue）・PR 作成
      ※ テスト設計の出力は check-test-matrix.sh（phase=unit）のハードゲートを通過しないとコミット/PR に進まない
      ※ 結合テスト(IT) は製造では設計・実施とも行わず、結合テスト工程（/integration-test-from-design）で別途実施する
      ※ E2E は AWS 環境構築後に E2E リポジトリの別工程とし、現環境では実行しない（/e2e-from-design は凍結中）
      review : /review-implementation がコード差分と品質ゲート結果を評価
      fix    : /fix-implementation が同じ feature ブランチに追加コミット

8.5. /integration-test-from-design <フィーチャ>   ※製造とは別工程（結合テスト）
   └─ 該当フィーチャの構成 Issue が組み上がった後に、結合テストマトリクス(IT) の設計と @SpringBootTest + Testcontainers での実施を行い、RTM の IT 列を更新する。製造の各 Issue からは呼ばない。check-test-matrix.sh（phase=integration）で検証。

9. 人手レビュー（PR レビューと本番マージ判断）
```

### 改善ループ（Pattern 4）の終了条件

- `BLOCK == 0` を満たした iteration で **PASS** → 次フェーズへ
- 3 回反復しても BLOCK が残った場合は **ESCALATE** → 人手レビュー必須
- 状態は `.skills-state/<phase>/state.json` に保持される（gitignore 対象）

## 共通応答ルール

- ユーザーへの応答、要件定義書、設計書、作業ログ、説明文は、明示的な指定がない限り日本語で記述する。

## ドキュメントの正典（Source of Truth）

開発フローに関する記述は複数の文書に分散しているため、役割を次のとおり固定する。矛盾を見つけたらこの優先順位で解消し、重複記述は片方を参照に置き換える。

- **開発フローの正典**: 本ファイル（CLAUDE.md）。各フェーズの順序・成果物・ルールはここを最上位とする。
- **設計根拠**: `docs/architecture/skill-orchestration.md`（skill 連鎖の設計思想・状態機械・採択ゲート・整合チェック）。
- **運用手順の詳細**: `docs/process/`（レビュー基準・Issue 管理などの運用ガイド）。
- **技術スタックの正典**: 各子リポジトリの `.claude/rules/`（FE: `claude-poc-frontend/.claude/rules/frontend-*.md` / BE: `claude-poc-backend/.claude/rules/backend-*.md`）。フレームワーク・ライブラリ・バージョンはここにのみ記載し、CLAUDE.md・設計書・スキルは再掲せず参照する。矛盾時は frontend ルールを最優先（正）とする。親 `rules/` には横断 AI ルール（`rules/cross-cutting.md`）のみを置く（`docs/process/リポジトリ構成と移行計画.md`）。
- **正典の保護（機械的強制）**: 親 `rules/` 配下・親 CLAUDE.md・各子リポジトリの `.claude/rules/` 配下は **Claude 実行中の編集を禁止**する（`.claude/hooks/protect-canon.sh` が PreToolUse で Edit/Write/MultiEdit/Bash 書き込みをブロック。パターン `(^|/)rules/` は子の `.claude/rules/` にも合致する）。正典の変更は人手で行う。Claude に編集を手伝わせる場合のみ、`ALLOW_RULES_EDIT=1` を設定したセッションで実行する。スキルの自動実行はフラグを立てないため常にブロックされ、ルールを書き換えて品質ゲートを通すことはできない。
- Agent Teams（experimental の teammate 機能）は使用しない。並列実行は Pattern 2（Parallel Fan-Out）で代替する。

## 技術スタックの正典と確定ルール

技術スタックは要件で**人間が指定する**。Claude は既定値で自動補完しない。未指定・未確定のまま設計・製造フェーズに進まない（**ハードゲート**）。

- **確定したスタックの正典は対象子リポジトリの `.claude/rules/` に集約する**。CLAUDE.md・設計書（`docs/design/方式設計.md` 等）・スキルでは、フレームワーク名・ライブラリ名・バージョンを**再掲しない**。必要な箇所では各子の `.claude/rules/` を参照する（二重管理の禁止）。
  - フロントエンド: `claude-poc-frontend/.claude/rules/frontend-*.md`
  - バックエンド: `claude-poc-backend/.claude/rules/backend-*.md`（実装規約。ビルド / DB / テスト / 静的解析 / カバレッジ閾値などのスタック確定値も、人間がここに追記して確定する）
  - リポジトリ構成・E2E の所在などの横断決定: `docs/process/リポジトリ構成と移行計画.md` に記録する
- **未指定時の挙動**: 採用技術が未確定のまま設計フェーズ（`design-from-requirements`）以降に進まない。対象子の `.claude/rules/` 上に「要確定」項目が残る間は中断し、人間に指定を求める。既定値による自動決定は禁止する。
- **機械的強制**: 確定状況は各子の `.claude/rules/[fe|be]*-00-stack.md`（技術スタック確定表）を正典とし、`design-loop` / `design-from-requirements` は開始前に `.claude/skills/_common/scripts/check-stack-decided.sh` を実行する。`要確定` が残る場合・確定表が存在しない場合（未記載 = 要確定）は exit 1 で設計着手をブロックし、未確定項目の一覧を人間に提示する。
- **矛盾時の優先順位**: 複数文書・複数選択肢で技術が食い違う場合は、**frontend ルール（`claude-poc-frontend/.claude/rules/frontend-*.md`）を最優先（正）** とし、他（CLAUDE.md の旧記述・設計書・スキル）はそれに合わせる。

## 開発ルール

- 実装前に要件定義と設計書を確認する。**要件定義（docs/requirements/）が存在しない場合は、先に /requirements-from-input を実行する**。
- 要件定義作成フェーズでは要件定義成果物の作成だけを行い、設計、実装、UT、静的解析、E2E には進まない。
- 設計書作成フェーズでは、採択済みの要件定義書を入力として設計成果物だけを作成する。設計時に要件の意思決定（業務ルール追加、画面新設、用語定義など）は行わない。
- 設計書は人手レビューと採択を経た後にのみ、後続の製造、UT、カバレッジ改善、静的解析、E2E へ進める。
- **採択ゲートは人間の明示アクションで強制する**。証跡はすべて GitHub に残す。**要件定義・設計書の採択 = docs リポジトリ（claude-poc-docs）の `main` への PR マージ**とし、人間が PR をレビューし `main` へマージすることが採択行為である（前提: docs の `main` に branch protection（PR 必須・レビュー必須・直 push 禁止）を設定する）。マージを契機に `create-issues-from-docs` workflow が後続 Issue（要件変更→設計書作成 Issue / 設計変更→実装 Issue）を自動起票する。**実装の開始 = 人間が対象 Issue に `@claude` とコメントすること**であり、Claude・skill が自らコメント・マージして起動してはならない。ローカル（親アンブレラ）から後続フェーズの skill（`design-from-requirements` / `ui-brief-from-design` / `create-issues-from-design` / `implement-from-issue`）を起動する場合は、開始前に入力ドキュメントが docs の `main` にマージ済みであることを確認し（`git log origin/main -- <パス>` 等）、未マージなら中断して人手レビュー・マージを依頼する。ループの `passed=true`（BLOCK==0）は採択とは別の関門であり、自動採択ではない。
- 既定の配置がない場合、要件定義成果物は docs/requirements、設計成果物は docs/design、テスト成果物は docs/test に置く。
- UI 設計を Claude Design（claude.ai/design）で行う場合は、設計フェーズ採択後に `/ui-brief-from-design` で `docs/design/ui-design/brief/` を生成する。ブリーフは「共通ブリーフ（`_共通.md`）+ 画面別ブリーフ」の2層構造とし、Claude Design へは共通ブリーフを先に投入してから画面別ブリーフをまとめて添付する。
- Claude Design の Export 物は `docs/design/ui-design/handoff/` 配下に **Export の構造そのまま**（`README.md` / `prototype/` / `tokens/` 等）で人手で格納する。prototype/ 配下の jsx は画面単位に分割せず、Claude Design が出力したカテゴリ単位（`wf-screens-*.jsx` 等）のまま保持する。設計書本体（`docs/design/screens/` 等）は書き換えない。
- 画面 ID（scr-id）と prototype 内の React 関数（例: `Scr100DashA`）の対応は `docs/design/ui-design/handoff/README.md` のマッピング表を Source of Truth とし、Issue 起票時に画面 Issue へ埋め込む。
- 画面ごとに画面 ID（SCR-001 形式・3 桁ゼロ埋め）を採番し、要件・設計・テスト全体で同じ ID を引用する。
- 画面遷移は Mermaid（`flowchart`）で図示し、ノードには画面 ID を使う。
- 要件定義では **ユースケース図** を `docs/requirements/ユースケース図.md` に必ず作成する。アクター × ユースケースの全体俯瞰を Mermaid（`flowchart` ベース、システム境界を `subgraph` で表現）で 1 枚に描き、各ユースケースには **ユースケース ID（UC-001 形式・3 桁ゼロ埋め）** を採番して、`概要.md` の主要ユースケース表および `functional/[機能名].md` の関連ユースケース欄から同 ID で引用する。
- 要件定義では **業務アクティビティ図** を `docs/requirements/activities/[フロー名].md` に業務フロー単位で作成する。応募→交渉→合意→運送→評価のような分岐を含む業務プロセスを Mermaid（`flowchart` ベース、判断ノードに `{ ... }` を用いる）で描き、各フローには **アクティビティ ID（ACT-001 形式・3 桁ゼロ埋め）** を採番する。関連するユースケース（UC-XXX）・業務ルール（BR-XXX）・受け入れ条件（AC-XXX）を本文中で明示的に引用する。フロー名は業務用語の日本語名（例: `案件成約フロー.md`）とする。
- 要件定義では **概念データモデル** を `docs/requirements/データモデル.md` に作成する。主要エンティティに **概念エンティティ ID（ENT-001 形式・3 桁ゼロ埋め）** を採番し、Mermaid `erDiagram` で関係と多重度を 1 枚に図示する。ステータスを持つエンティティについては **状態 ID（ST-001 形式・3 桁ゼロ埋め）** と状態遷移図（Mermaid `stateDiagram-v2`）を併記し、遷移条件は業務ルール（BR-XXX）から引用する。物理テーブル設計（カラム型・PK/FK・インデックス・物理テーブル名）は本ファイルでは扱わず、設計フェーズの `docs/design/DB定義.md` および `docs/design/tables/*.md` に委ねる。
- 要件定義では **外部インターフェース一覧** を `docs/requirements/外部インターフェース一覧.md` に作成し、メール送信・バッチ・外部システム連携・ファイル授受などの外部 IF に **外部 IF ID（EXT-001 形式・3 桁ゼロ埋め）** を採番する。各 IF の用途・トリガ・データ・失敗時挙動・第 1 版での要否を業務観点で記述する。第 1 版で対象外とする IF も明示し、「外部 IF なし」と判断する場合もその旨と根拠を残す。
- 要件定義では **移行要件** を `docs/requirements/移行要件.md` に作成し、初期データ・マスタデータ・既存データ移行に **移行要件 ID（MIG-001 形式・3 桁ゼロ埋め）** を採番する。投入タイミング・件数規模・完了判定基準・切り戻し方針を記述する。「移行なし」と判断する場合もその旨を明記する。
- 要件定義では **権限（認可）マトリクス** を `docs/requirements/権限マトリクス.md` に作成し、ロール × ユースケース（UC-XXX）/リソース（ENT-XXX・SCR-XXX）の操作可否（C/R/U/D・状態遷移）と、テナント越境アクセスの拒否条件を一覧化する。設計フェーズの認可設計（`docs/design/認可設計.md` / `セキュリティ設計.md`）の入力とする。ロールが 1 種で認可制御が不要な場合もその旨と根拠を明記する。
- 要件定義では **メッセージ一覧** を `docs/requirements/メッセージ一覧.md` に作成し、エラー・警告・情報・確認・バリデーション・通知の利用者向け表示文言に **メッセージ ID（MSG-001 形式・3 桁ゼロ埋め）** を採番する。区分 / 文言 / 表示画面（SCR-XXX）/ トリガを記述し、未確定文言は本文に断定で書かず `オープン課題.md`（`Q-MSG*`）に切り出す。設計の ErrorResponse コード・通知文面と MSG-XXX で相互参照する。
- 要件定義では **コード値定義** を `docs/requirements/コード値定義.md` に作成し、業務区分値（ステータス・種別等）の概念レベルの正典を置く（区分名 / コード値 / 表示名 / 意味 / 関連 BR・状態 ST）。設計フェーズの `_common.yaml` の enum はこれを物理化したものとして対応づける。「区分値なし」の場合もその旨を明記する。
- 要件定義では **通知・文面定義** を `docs/requirements/通知・文面定義.md`（または `メッセージ一覧.md` に統合）に作成し、通知タイプ・送信メールの件名 / 本文 / 差込変数 / 関連 UC・BR・EXT を記述する。第 1 版で通知・メールが無い場合もその旨を明記する。
- 非機能要件のうち **パスワードポリシー・セッション有効時間・通信暗号化・対象ブラウザ・対象デバイス・バックアップ最低頻度・障害検知/通知方法・稼働時間帯** は設計着手前に確定する。未確定値を本文に「TBD」で残さず、`docs/requirements/オープン課題.md` の `Q-NF*` に切り出して本文からは参照する。
- **採用技術スタックは設計着手前に各子リポジトリの `.claude/rules/` で確定する**（ハードゲート）。FW・ビルド・DB 製品・マイグレーション・テスト/静的解析ツール・カバレッジ閾値・E2E の所在・リポジトリ構成を `claude-poc-frontend/.claude/rules/frontend-*.md`・`claude-poc-backend/.claude/rules/backend-*.md` に確定させ、`.claude/rules/` 上に「要確定」項目が残る間は `design-from-requirements` 以降に進まない。Claude は未指定スタックを既定値で補完せず、人間に指定を求める。技術名・ライブラリ・バージョンは各子の `.claude/rules/` にのみ記載し、CLAUDE.md・設計書・スキルでは再掲しない（矛盾時は frontend ルールを正とする）。
- `docs/requirements/オープン課題.md` の冒頭には **クローズ運用ルール章** を必ず置き、「設計着手前にクローズ必須の課題区分」と「設計フェーズへ持ち越して良い課題区分」を明示する。`Q-NF*`（セキュリティ・運用ベースライン）、`Q-DM*`（データモデル）、`Q-EI*`（外部 IF）、`Q-MIG*`（移行）に該当する課題は設計フェーズ起動前に closed にする（要件採択者の責務）。
- 要件定義作成・レビュー・修正の全工程で `.claude/skills/requirements-guardrails/` の **ガードレール（MUST NOT）と文書間整合チェック** を適用する。詳細: ネガティブパターン（カテゴリ A〜D）は `references/negative-patterns.md`、非機能要件の要求値テンプレは `references/nonfunctional-template.md`、文書間整合（ステータス遷移／画面遷移／用語）の確認手順は `references/consistency-checklist.md`。未確定事項は本文に断定で書かず `> **[要確認]** {内容} / 選択肢A / 選択肢B / 影響範囲 / 確認期限` 形式で残し、同内容を `オープン課題.md` に転記する。
- 設計では **シーケンス図** を `docs/design/sequences/[シーケンス名].md` にシーケンス単位で作成する。フロントエンド ↔ API ↔ DB（必要に応じて外部システム）の交互動作を Mermaid（`sequenceDiagram`）で描き、各シーケンスには **シーケンス ID（SEQ-001 形式・3 桁ゼロ埋め）** を採番する。対応する画面 ID（SCR-XXX）・API（`api/[リソース名].yaml` の operationId）・ユースケース（UC-XXX）・受け入れ条件（AC-XXX）を本文中で明示的に引用する。シーケンス名は業務用語の日本語名（例: `応募確定.md`）とする。
- API は OpenAPI 3.1 準拠の YAML をリソースごとに 1 ファイルで定義し（1 ファイル内に同リソースの全 HTTP メソッドを集約）、共通スキーマは `docs/design/api/_common.yaml` に集約して `$ref` で参照する。
- DB は `docs/design/DB定義.md` に全体方針 + 全体 ER 図（Mermaid `erDiagram`）を置き、テーブル単位の詳細は `docs/design/tables/[テーブル名].md` に分割して部分 ER 図を必ず含める。
- 設計では **方式設計** を `docs/design/方式設計.md` に作成し、論理／物理アーキテクチャ・コンポーネント構成・環境別（dev/stg/prod）デプロイ構成・ミドルウェア構成を Mermaid で図示する。開発環境（devcontainer）ではなく本番方式を対象とする。
- 設計では **セキュリティ設計** を `docs/design/セキュリティ設計.md` に作成し、認証・認可の正典を 1 箇所に集約する（JWT ライフサイクル・署名/失効・リフレッシュ・CORS 許可オリジン・パスワードハッシュ方式・ログイン試行制御・`@PreAuthorize` 規約とテナントフィルタの実装方式）。要件 `権限マトリクス.md` を物理化した **認可設計**（API operationId × 必要ロール × テナント条件）を内包するか `docs/design/認可設計.md` に分割する。
- 設計では **バッチ設計**（`docs/design/バッチ設計.md`）と **共通部品設計**（`docs/design/共通部品設計.md`）を作成する。バッチ設計はトランザクション単位・再実行・件数規模時の分割・監視連携・失敗時詳細を `IF定義.md` の IF 粒度から詳細化する（バッチが無い場合はその旨を明記）。共通部品設計は共通例外ハンドラ・バリデーション共通化・共通レスポンス整形・ロギング方式（ErrorResponse スキーマの実装方式を含む）を定める。
- 設計では **運用設計** を `docs/design/運用設計.md` に作成し、監視項目・アラート閾値・バックアップ/リストア手順・ジョブ運用・ログ保持と監査ログ出力箇所を定める。`非機能要件.md` の運用・可用性の要求値を設計に落とし、要求値と突合できるようにする。
- 変更は差分が追いやすい加算型を優先し、無関係なファイルは書き換えない。
- バックエンドの実装規約（アーキテクチャ・レイヤー責務・パッケージ構成・命名）は **`claude-poc-backend/.claude/rules/backend-*.md`（正典）に従う**。CLAUDE.md ではバックエンド実装規約を再掲しない（二重管理の禁止）。バックエンドは画面描画を持たず、JSON ベースの REST API のみを提供する方針は維持する。
- フロントエンドのディレクトリ構成・状態管理・API 連携・ルーティング・認可・テストの規約は **`claude-poc-frontend/.claude/rules/frontend-*.md`（正典）に従う**。CLAUDE.md ではフロント実装規約を再掲しない（二重管理の禁止）。表示ロジックは単純に保ち、業務判定やデータ整形はバックエンドの Service 側に寄せる方針は維持する。
- フロントエンドとバックエンドの境界は OpenAPI 3.1 で定義した REST API とし、認証は JWT などのトークンベースで CORS 設定を明示する。
- DB 変更では明示的な migration を作成し、Entity、Repository、DDL、`docs/design/tables/*.md` の整合を保つ。
- 要件または受け入れ条件（AC-XXX）ごとに、少なくとも 1 つの実行可能なテストへ対応付ける。テストには **テストケース ID（単体は TC-001 形式、E2E は E2E-001 形式・いずれも 3 桁ゼロ埋め）** を採番し、`docs/test/単体テストマトリクス.md` および E2E シナリオ表で AC-XXX・SCR-XXX と相互参照する。各テストは **正常系 / 異常系（入力エラー）/ 境界値 / 権限境界** の区分を明示する。
- テストは **単体（TC-XXX）/ 結合（IT-XXX）/ E2E（E2E-XXX）** の 3 層で設計する。結合テストは `docs/test/結合テストマトリクス.md` に **結合テストケース ID（IT-001 形式・3 桁ゼロ埋め）** を採番し、Controller→Service→Repository→DB の実結合・サービス間結合（通知発火 × トランザクション境界・排他制御）を AC-XXX・SCR-XXX・API operationId と相互参照する。単体（Service モック）と E2E（ブラウザ）の中間層を埋める。**結合テストの設計（IT マトリクス）と実施は製造から分離した結合テスト工程（`/integration-test-from-design`）が担い、製造（implement-loop）では行わない**（複数 Issue をまたぐため。E2E と同様の切り分け）。
- 製造フェーズでは、テスト実施（実行・カバレッジ）とは別に **単体テスト設計（マトリクス）を `/test-design-from-issue` で必ず出力する**（2 タッチ＝実装と並行ドラフト→実装後に実コード整合で確定）。`docs/test/単体テストマトリクス.md`(TC) と `docs/test/トレーサビリティマトリクス.md`(RTM) を `check-test-matrix.sh ... unit` で機械検証し、未充足ならコミット/PR に進まない（ハードゲート）。AC-XXX が無い基盤 Issue でも設計書「実装内容」項目を観点化して TC を採番し省略しない。結合テスト(IT) は結合テスト工程の責務。
- **非機能要件の要求値ごとに少なくとも 1 つの検証**を `docs/design/非機能テスト計画.md` に対応づける（性能・負荷・可用性）。要求値 → 検証方法・目標値・シナリオの対応表を必須とする。脆弱性観点（認可バイパス・IDOR/テナント越境・JWT 改ざん・機微情報のレスポンス/ログ漏えい等）は `docs/design/セキュリティテスト観点.md`（テストデータ設計・全体テスト計画を含めてよい）に整理する（戦略・計画は設計フェーズ、ケース化したマトリクスは `docs/test/`。単体マトリクス(TC)・RTM は製造フェーズ、結合マトリクス(IT) は結合テスト工程）。
- 要件→設計→Issue→テストの追跡は `docs/test/トレーサビリティマトリクス.md`（RTM）に 1 表で集約する（列: UC / AC / BR / SCR / API operationId / Issue# / TC-XXX / IT-XXX / E2E-XXX）。ペアワイズの追跡（review-design / 各マトリクス）に加え、横串でカバレッジ漏れを検出するための正典とし、Issue 起票・実装ループで更新する。
- 実装フェーズの品質ゲートには **セキュリティレビュー観点**（OWASP ベース: 認可バイパス・IDOR/テナント越境・機密情報のログ出力・JWT 検証・入力サニタイズ等）を含め、PR 作成前に `review-implementation` の `security` 観点で点検する。`docs/test/セキュリティテスト観点.md` と対応づける。
- ドキュメントで ID または略号（例: `SCR-001`、`AC-001`、`Q-A1` などの英字プレフィックス + 連番、機能カテゴリ略号、独自の命名コードなど）を導入する場合は、当該ドキュメントの冒頭付近に **凡例（略号一覧表）を必ず明記** する。凡例には少なくとも「略号」「対応する正式名称（日本語）」「補足（必要に応じて）」を含め、新規略号を追加した場合は同じファイル内の凡例を更新する。CLAUDE.md など複数ドキュメントから参照される共通 ID（例: `SCR-XXX` の採番ルール）は CLAUDE.md 側で全体定義し、個別ドキュメント側はそれを参照する形でも可。略号を新規導入する skill / 人手作業は、凡例の出力／更新まで含めて 1 つの成果物として完成させる。
- カバレッジ改善ではアプリケーションコードを優先し、除外は必ず理由を明記する。
- 静的解析は新規ツール導入より先に、既存設定済みツールを利用する。
- review 系 skill（`review-requirements` / `review-design` / `review-implementation`）は `bash .claude/skills/_common/scripts/check-truncation.sh <対象パス>` を呼び、ファイルの **切断検出** を機械的に実施する。Invalid UTF-8（マルチバイト文字途中切断）は BLOCK、末尾の不完全な日本語文・Markdown テーブル行の `|` 未閉じ・末尾近傍の括弧未閉じは SUGGEST、末尾改行なしは NIT として review JSON の `findings` に取り込む。

## 推奨ドキュメント一式

### 要件定義（docs/requirements/）

- docs/requirements/概要.md
- docs/requirements/業務ルール.md
- docs/requirements/functional/[機能名].md（機能ごとに 1 ファイル、業務用語の日本語名。例: `アカウント登録.md`）
- docs/requirements/ユースケース図.md（UC-XXX 採番 + Mermaid ユースケース図、全体俯瞰 1 枚）
- docs/requirements/activities/[フロー名].md（業務フローごとに 1 ファイル、`案件成約フロー.md` 等の日本語名、ACT-XXX 採番 + Mermaid アクティビティ図）
- docs/requirements/画面一覧.md（画面 ID 一覧 + Mermaid 画面遷移図）
- docs/requirements/データモデル.md（ENT-XXX 採番 + 概念 ER 図 / Mermaid `erDiagram` + ステータスを持つエンティティの状態遷移 ST-XXX。物理テーブル設計は設計フェーズの責務）
- docs/requirements/外部インターフェース一覧.md（EXT-XXX 採番。メール送信・バッチ・外部システム連携。第 1 版で対象外とする IF も明示する。「外部 IF なし」の場合もその旨を明記）
- docs/requirements/移行要件.md（MIG-XXX 採番。初期データ・マスタデータ・既存データ移行方針。「移行なし」の場合もその旨を明記）
- docs/requirements/権限マトリクス.md（ロール × ユースケース/リソース（UC/ENT/SCR）の操作可否一覧 + テナント越境拒否条件。設計の `認可設計.md` / `セキュリティ設計.md` の入力。「ロール 1 種・認可制御なし」の場合もその旨を明記）
- docs/requirements/メッセージ一覧.md（MSG-XXX 採番。エラー・警告・情報・確認・バリデーション・通知の利用者向け表示文言の正典。区分 / 文言 / 表示画面(SCR-XXX) / トリガ。未確定は `Q-MSG*` へ切り出し）
- docs/requirements/コード値定義.md（業務区分値（ステータス・種別）の概念レベル正典。区分名 / コード値 / 表示名 / 意味 / 関連 BR・ST。設計 `_common.yaml` の enum と対応。「区分値なし」の場合もその旨を明記）
- docs/requirements/通知・文面定義.md（通知タイプ・送信メールの件名/本文/差込変数/関連 UC・BR・EXT。`メッセージ一覧.md` に統合しても可。通知・メールが無い場合もその旨を明記）
- docs/requirements/非機能要件.md（性能・可用性・セキュリティ・ログ・運用・データ保持・アクセシビリティ。**パスワードポリシー / セッション / 対象ブラウザ / バックアップ / 障害通知 / 稼働時間帯** はベースラインとして設計着手前に確定する）
- docs/requirements/ブランドガイドライン.md（任意。UI 設計で参照するブランド / ペルソナ / デザインシステム指針）
- docs/requirements/用語集.md
- docs/requirements/オープン課題.md（**設計着手前にクローズ必須の課題区分とクローズ手順章を冒頭に含める**）

### 設計（docs/design/）

- docs/design/概要.md
- docs/design/screens/画面遷移.md（Mermaid 画面遷移図）
- docs/design/screens/[scr-id]-[画面名].md（**画面仕様書**。画面ごとに 1 ファイル、`SCR-XXX-画面名.md` 形式の日本語名、画面 ID 明記。1 画面 = 1 ファイルに 表紙 / 改訂履歴 / 画面概要 / 画面遷移 / 画面レイアウト（ワイヤーフレーム + ボタン定義表）/ 表示項目（エリアごとの項目定義表）/ 機能概要 / イベント一覧 / 振る舞い定義（Given-When-Then + Mermaid 処理フロー）/ 業務ルール / メッセージ（MSG-XXX）/ 権限マトリクス / テーブルアクセス / 未解決事項（OQ-XXX）を内包する。章構成の正典は `design-from-requirements/design-spec-template.md`。物理 DDL/SQL は `tables/*.md`・`DB定義.md`、API スキーマは `api/*.yaml` を正典とし、画面仕様書からは参照する（レガシー由来の Legacy Source 表・SQL定義・DTO↔DB データマッピング・移行ノートは出力しない））
- docs/design/sequences/[シーケンス名].md（主要シーケンスごとに 1 ファイル、`応募確定.md` 等の日本語名、SEQ-XXX 採番 + Mermaid `sequenceDiagram`）
- docs/design/api/_common.yaml（API 共通スキーマ、OpenAPI 3.1 components）
- docs/design/api/[リソース名].yaml（リソースごとに 1 ファイル、`[resource].yaml` 形式の kebab-case 英語、OpenAPI 3.1 準拠。例: `jobs.yaml`, `users.yaml`, `applications.yaml`）
- docs/design/IF定義.md
- docs/design/DB定義.md（全体 ER 図 / Mermaid `erDiagram`）
- docs/design/tables/[テーブル名].md（テーブルごとに 1 ファイル、DB 物理名と同じ snake_case 英語、部分 ER 図 / Mermaid `erDiagram`）
- docs/design/方式設計.md（論理／物理アーキテクチャ・コンポーネント構成・環境別デプロイ構成・ミドルウェア構成を Mermaid で図示。本番方式が対象）
- docs/design/セキュリティ設計.md（認証・認可の正典。JWT ライフサイクル / CORS / パスワードハッシュ / ログイン試行制御 / `@PreAuthorize` 規約・テナントフィルタ）
- docs/design/認可設計.md（API operationId × 必要ロール × テナント条件。要件 `権限マトリクス.md` の物理化。`セキュリティ設計.md` に統合しても可）
- docs/design/バッチ設計.md（バッチごとのトランザクション単位・再実行・分割・監視連携・失敗時詳細。`IF定義.md` の IF 粒度を詳細化。「バッチなし」の場合もその旨を明記）
- docs/design/共通部品設計.md（横断的関心事。共通例外ハンドラ / バリデーション共通化 / 共通レスポンス整形 / ロギング方式。ErrorResponse の実装方式を含む）
- docs/design/運用設計.md（監視項目・アラート閾値 / バックアップ・リストア手順 / ジョブ運用 / ログ保持・監査ログ出力箇所。非機能要件の運用・可用性要求値を設計に落とす）
- docs/design/テスト戦略.md
- docs/design/シナリオ戦略.md
- docs/design/非機能テスト計画.md（性能・負荷・可用性。非機能要件の要求値ごとに検証方法・目標値・シナリオを対応づける）
- docs/design/セキュリティテスト観点.md（認可バイパス・IDOR/テナント越境・JWT 改ざん・機微情報漏えい等の脆弱性観点。テストデータ設計・全体テスト計画を含めてよい。任意・推奨）
- docs/design/ui-design/brief/README.md（UI ブリーフ索引と Claude Design 投入手順、任意）
- docs/design/ui-design/brief/_共通.md（全画面共通の DS / 共通コンポーネント / ロール / トーン & ボイス / 全画面横断のルール、任意・推奨）
- docs/design/ui-design/brief/[scr-id]-[画面名].md（画面ごとの UI 設計ブリーフ。`_共通.md` からの **差分のみ** を記述、対応する設計 md と同じ日本語名、任意）
- docs/design/ui-design/handoff/（Claude Design の Export 物を **Export 構造そのまま** 人手で格納するディレクトリ、任意）
    - docs/design/ui-design/handoff/README.md（Export の README。scr-id → prototype 関数のマッピング表を含む、Source of Truth）
    - docs/design/ui-design/handoff/prototype/（Export の prototype/ 配下を分割せずそのまま格納。`wf-screens-*.jsx` 等のカテゴリ単位ファイルを保持）
    - docs/design/ui-design/handoff/tokens/（Export の tokens/ 配下を分割せずそのまま格納）

### テスト（docs/test/）

- docs/test/単体テストマトリクス.md（TC-XXX 採番。AC-XXX・BR-XXX・SCR-XXX と相互参照）
- docs/test/結合テストマトリクス.md（IT-XXX 採番。Controller→Service→Repository→DB 実結合・サービス間結合。AC-XXX・SCR-XXX・API operationId と相互参照。**製造ではなく結合テスト工程 `/integration-test-from-design` の成果物**）
- docs/test/トレーサビリティマトリクス.md（RTM。UC / AC / BR / SCR / API operationId / Issue# / TC-XXX / IT-XXX / E2E-XXX を 1 表に集約しカバレッジ漏れを検出）

> テストの「戦略・計画・観点」（テスト戦略 / シナリオ戦略 / 非機能テスト計画 / セキュリティテスト観点）は設計フェーズ成果物として `docs/design/` に置き、「ケース化したマトリクス」は `docs/test/` に置く。**単体テストマトリクス(TC) と RTM は製造フェーズ、結合テストマトリクス(IT) は結合テスト工程**の成果物（実施タイミングが異なるため工程を分ける。E2E はさらに別工程）。
