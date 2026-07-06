# 横断レビュー 6 観点 + データ連鎖 E2E 詳細

review-implementation-overall 本文から 2026-07-02 に PP-5 分解で外出し。本文の該当手順から参照される。

#### 観点 A: 設計書との全体整合 + データ連鎖 E2E（design_coverage / design_mismatch / data_sufficiency / code_value_chain）

- 設計に在って実装に無い: 未実装の operationId・テーブル・画面・バッチ（**実装漏れ = BLOCK**）
- 実装に在って設計に無い: 設計外のエンドポイント・テーブル・カラム・画面・ジョブ（**設計逸脱 = BLOCK**）
- スキーマ不一致: リクエスト/レスポンス型・ErrorResponse 形式・MSG-XXX 文言の食い違い
- 画面: `screens/SCR-*.md` の項目・バリデーション・遷移（`画面遷移.md`）⇔ FE 実装の突合
- **データ連鎖の E2E 突合（data_sufficiency）**: 各画面の**表示項目・業務判定値**を起点に「画面項目 → API レスポンスフィールド（operationId）→ DB カラム（Entity / table）」の供給経路をエンドツーエンドで辿る。途中のどこか（API が当該フィールドを返さない / DB カラムが無い / FE がそのフィールドを読んでいない）で連鎖が切れていれば **`data_sufficiency` 欠落 = BLOCK**。とくにログイン直後の画面・共通レイアウト（ヘッダー等）の表示項目が `LoginResponse` または `/me` 相当 API から取得できない場合は BLOCK。連鎖を辿った対応表を md サマリに根拠として含める。
- **コード値 4 層統一（code_value_chain）**: 区分値（ステータス・種別）の enum を **要件 `コード値定義.md` → 設計 `_common.yaml` → BE enum → FE const** の 4 層で突合する。いずれかの層で値・表示名が不一致、または下流の層に存在しない値があれば指摘（4 層が一致しない＝ BLOCK）。

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

#### 観点 C: セキュリティ横断（security / authorization）

- 認可設計 × 実装の**全 API 突合**: BE の `@PreAuthorize` 漏れ・ロール不一致（**1 件でも BLOCK**）。FE のルートガード・ロール別表示制御の漏れ（FE は UX 層であり防御の正は BE、ただし要件 `権限マトリクス.md` との不整合は指摘）
- テナント越境: テナントフィルタの適用漏れ箇所の網羅点検、IDOR（ID 直指定での他テナント資源参照）。**テナントフィルタは SELECT だけでなく UPDATE / DELETE / COUNT / 集計クエリの全クエリ種別に適用されているか**を網羅点検する（1 種別でも漏れがあれば BLOCK）
- **状態遷移（ST-XXX）の網羅（state_transition）**: 設計の状態遷移図（`データモデル.md` の ST-XXX / `stateDiagram-v2`）の**全遷移**が実装にあり、かつ**不正遷移（許可されない状態間の遷移）を拒否する**実装（条件付き UPDATE・ガード）が存在するか。さらに**全遷移＋不正遷移拒否のテストが網羅**されているか（網羅が薄い遷移は指摘、不正遷移拒否テストが皆無なら BLOCK）
- **通知発火点の網羅（notification）**: 設計（`通知・文面定義.md` / シーケンス）で通知が発火するとされた全イベント（成約・合意・キャンセル等）に対し、実装の発火点（`ApplicationEventPublisher` 等）が存在し漏れが無いか。発火点の過不足・トランザクション境界（コミット後発火か）を突合する
- **監査ログの突合（audit_log）**: `運用設計.md` で監査ログ出力箇所と定義された操作（認可変更・状態遷移・機微データ参照等）に対し、実装に監査ログ出力があるか。出力が欠落している操作を指摘する
- JWT 検証（署名・失効・有効期限）の一貫性、FE のトークン保管方式（`セキュリティ設計.md` との突合）、CORS 設定の整合
- XSS（FE: `dangerouslySetInnerHTML` 等の生 HTML 挿入）、機微情報のログ・レスポンス・FE バンドルへの漏えい、ハードコードされたシークレット
- `docs/design/セキュリティテスト観点.md` の各観点に対する実装・テストの対応状況

#### 観点 D: RTM/テスト網羅の横串（traceability / rtm_gap）

- 各リポの RTM を正典として UC / AC / BR / SCR / operationId → TC-XXX の対応を全行点検し、**単体テストが 1 件も無い AC（真のカバレッジ穴）は BLOCK**
- RTM に行が無い実装済み Issue・operationId・画面（RTM の記載漏れ）
- **幽霊 TC の検出（ghost_tc）**: マトリクス上の TC-XXX と実テストコードの乖離（採番だけあって実テストメソッドが存在しない、または別の内容を指している＝「幽霊 TC」）。マトリクスの全 TC-XXX を実テストコードへ突合し、実体の無い TC を列挙する
- 区分（正常系 / 異常系 / 境界値 / 権限境界）の網羅が薄い領域の指摘
- ※ IT-XXX / E2E-XXX 列の未整備は**指摘しない**（結合テスト工程・E2E 工程の責務）

#### 観点 E: リポジトリ間整合（cross_repo_consistency）※対象が 2 リポ以上の場合

OpenAPI（`docs/design/api/*.yaml`）を境界の正典として FE⇔BE⇔batch を突合する。

- **三者一致（type_three_way）**: OpenAPI（`docs/design/api/*.yaml`）⇔ FE の TypeScript 型 ⇔ BE の Request/Response DTO で、フィールド名・型・nullable/必須が一致するか。**Jackson の getter 名ベースシリアライズによる実 JSON フィールド名の乖離（DTO の `errorCode` ⇔ FE が読む `code`、`@JsonProperty` の有無等）を含めて**突合する（不一致は BLOCK）
- FE の API クライアントの型・パス・メソッド ⇔ BE の実装の不一致（設計を経由しない「実装同士の暗黙の合意」は設計逸脱として BLOCK）
- enum・コード値・MSG-XXX 文言の FE/BE での二重定義・食い違い
- 認可のずれ: BE が拒否するロールの操作が FE で表示・実行可能（またはその逆）
- batch ⇔ BE の共有テーブル・トランザクション境界・排他制御の整合

#### 観点 F: UI handoff prototype ⇔ FE 実装の対応（ui_handoff）※工程#5・対象に frontend を含む場合

Claude Design の Handoff（`docs/design/ui-design/handoff/`）を使った場合に、prototype と FE 実装の対応を目視確認できる対応表を出す。

- `docs/design/ui-design/handoff/README.md` の **scr-id → prototype 関数（`wf-screens-*.jsx :: ScrXXXName`）マッピング表**を読み、各 prototype 関数に対応する FE の画面コンポーネント実装が存在するかを突合する。
- 各画面について「prototype 関数 ⇔ FE コンポーネント ⇔ 実装状況（実装済 / 未実装 / 別実装）」の**対応表を md サマリに出力**する（ビジュアル一致の機械判定はしない＝人間の目視確認用）。
- prototype に在るのに FE 実装が無い画面、FE に在るのに prototype マッピングに無い画面を列挙する（前者は実装漏れの疑い、後者は設計外画面の疑いとして観点 A と突合）。
- handoff が存在しない（Claude Design 未使用）場合は本観点をスキップし、その旨をサマリに明記する。
