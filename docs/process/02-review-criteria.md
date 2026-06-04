# ② AI 成果物レビュー基準

最終更新: 2026-05-27

本文書は、AI が生成した成果物を **誰が・いつ・何を見て・どう判定するか** を定義します。マトリクス（フェーズ × 観点）とチェックリスト（成果物種別ごと）の二層で構成し、既存の `review-*` skill の判定基準と整合させています。

---

## 1. 重大度の定義

すべての AI レビュー（自動レビュー / 人手レビュー双方）は次の三段階で重大度を付ける。

| 重大度 | 定義 | 取り扱い |
|--------|------|----------|
| **BLOCK** | 後続フェーズの実行を阻害する。実装者が判断不能、設計と矛盾、セキュリティ欠落、トレーサビリティ断絶など。 | **0 件にならない限り PASS しない**。fix skill が必ず修正対象にする。 |
| **SUGGEST** | 修正が望ましいが PASS は妨げない。表記揺れ、冗長性、テスト検証可能性の不足、リスク先読みなど。 | fix skill は対応するが、残存しても PASS 可。 |
| **NIT** | 末尾空白、誤字、好みの差。 | fix skill は **無視**。人手で気づいたら直す。 |

> 出典: `docs/architecture/skill-orchestration.md` §1 指針 6・7、`.claude/skills/review-requirements/SKILL.md`、CLAUDE.md「スキルオーケストレーション運用ガイダンス」。

### 1.1 BLOCK 判定の典型例

- 機能要件で参照される画面 ID が `画面一覧.md` に存在しない（traceability 断絶）。
- API スキーマと DB Entity でフィールド型が不一致（consistency 違反）。
- 受け入れ条件（AC-XXX）に対応するテストが 1 つもない（completeness 不足）。
- 認証・認可の設計が欠落、または平文パスワード保存等の明確な脆弱性（security）。
- 用語が `用語集.md` と矛盾、または同一概念に複数表記（ambiguity）。

### 1.2 SUGGEST の典型例

- 同じ業務ルールが 2 箇所に書かれている（DRY 違反、要集約）。
- 命名がプロジェクト規約と僅かに異なる。
- テストケースは存在するが境界値が網羅されていない。
- エラーメッセージが UX 上もう少し親切にできる。

---

## 2. フェーズ × 観点マトリクス

各フェーズ（要件 / 設計 / 実装）で、レビューが必ずカバーすべき観点を以下のマトリクスで規定する。**列が観点、行がフェーズ**。○ = 主要観点、△ = 補助観点、— = 対象外。

| 観点 \ フェーズ | 要件定義 | 設計 | 実装 |
|----------------|:--------:|:----:|:----:|
| Completeness（成果物の網羅性） | ○ | ○ | ○ |
| Consistency（内部整合・前後フェーズ整合） | ○ | ○ | ○ |
| Traceability（要件↔設計↔実装↔テストの追跡） | ○ | ○ | ○ |
| Ambiguity（用語・記述の曖昧性） | ○ | △ | — |
| Security（認証・認可・入力検証・機密管理） | ○ | ○ | ○ |
| Architecture（責務分離・標準スタック準拠） | — | ○ | ○ |
| Design Mismatch（設計と実装の乖離） | — | — | ○ |
| Quality Gate（UT・静的解析・E2E の合否） | — | — | ○ |
| Coverage（カバレッジ閾値） | — | — | ○ |
| Git Hygiene（ブランチ・コミット・PR） | — | — | ○ |

> 出典: `.claude/skills/review-requirements/SKILL.md` §チェック観点、`.claude/skills/review-implementation/SKILL.md` §チェック観点。

### 2.1 観点ごとの判定基準（マトリクス補足）

- **Completeness**: 推奨ドキュメント一式（CLAUDE.md §「推奨ドキュメント一式」）と Issue 受け入れ条件をすべて満たすか。
- **Consistency**: 画面 ID、API パス、フィールド名、用語が全文書で一致するか。
- **Traceability**: 要件 → 画面 ID → 設計書 → Issue → 実装 → テストの鎖が切れていないか。各 AC-XXX に対応する実行可能テストが 1 つ以上あるか。
- **Ambiguity**: 主語不明、定量条件不明、未定義語の使用、相対表現（"高速に"等）の濫用。
- **Security**: OWASP Top 10 観点・JWT 設計・CORS 設定・機密の取り扱い・SQL/XSS インジェクション対策。
- **Architecture**: Controller 薄・Service 業務ロジック・Repository 永続化・Presentational / Container 分離・API サービス層集約。
- **Design Mismatch**: Issue 記載の AC・API スキーマ・ER 図と実装の差分。
- **Quality Gate**: UT pass / Checkstyle・PMD・SpotBugs / ESLint・型チェック / Playwright E2E がすべて green。
- **Coverage**: バックエンド JaCoCo、フロントエンド Vitest/Jest（Istanbul）の **プロジェクト規定閾値** を満たす。除外は理由を明記。
- **Git Hygiene**: feature ブランチ命名規約、コミットメッセージ規約、PR テンプレ、CI green。

---

## 3. 成果物種別チェックリスト

各成果物を AI 生成・人手作成のいずれかで作る際、レビュア（人または review skill）が確認する具体項目。

### 3.1 要件定義書（`docs/requirements/`）

- [ ] `概要.md` に背景・目的・スコープ・対象外・主要ステークホルダが揃う
- [ ] `業務ルール.md` の各ルールに ID が振られている
- [ ] `functional/*.md` が機能単位で分割され、AC-XXX が定義されている
- [ ] `画面一覧.md` に画面 ID 一覧 + Mermaid 画面遷移図がある
- [ ] `非機能要件.md` で性能・可用性・セキュリティ・運用が定量条件付きで書かれている
- [ ] `用語集.md` に主要用語と定義が網羅され、表記揺れがない
- [ ] `オープン課題.md` に未解決事項が分類されて残されている
- [ ] AC ↔ 機能要件 ↔ 画面 ID の相互参照が切れていない
- [ ] 設計や実装方式の意思決定が含まれていない（スコープ外混入）

### 3.2 設計書（`docs/design/`）

- [ ] `概要.md` で全体方針が要約されている
- [ ] `screens/画面遷移.md` の Mermaid `flowchart` が要件側の遷移と一致
- [ ] `screens/SCR-XXX-*.md`（`SCR-XXX-画面名.md` 形式の日本語名）がすべての画面 ID 分存在し、画面 ID が明記されている
- [ ] `api/_common.yaml` の共通スキーマを各 API が `$ref` で参照している
- [ ] `api/*.yaml`（リソース単位で 1 ファイル、同リソースの全 HTTP メソッドを集約）が OpenAPI 3.1 準拠でバリデート可能
- [ ] `IF定義.md` に外部 IF・内部 IF・認証方式が記述されている
- [ ] `DB定義.md` に全体 ER 図（Mermaid `erDiagram`）がある
- [ ] `tables/*.md` がすべてのテーブル分存在し、**部分 ER 図** がある
- [ ] `テスト戦略.md` と `シナリオ戦略.md` でテスト方針が明文化されている
- [ ] 要件 ID・画面 ID・AC が引用され、トレーサビリティが保たれている

### 3.3 UI ブリーフ / ハンドオフ（任意）

- [ ] `docs/design/ui-design/brief/_共通.md`（全画面共通の DS・共通コンポーネント・ロール・トーン・状態規約）が存在し、Claude Design 投入用プロンプトが末尾にある
- [ ] `docs/design/ui-design/brief/SCR-XXX-*.md`（対応する設計 md と同じ日本語名）が必要な画面分存在し、`_共通.md` からの **差分のみ** で構成されている（DS・共通コンポーネントの再掲がない）
- [ ] `docs/design/ui-design/brief/README.md` に「共通 → 画面別」の投入手順と `ui-design/handoff/` の格納ルール（Export 構造そのまま）が記載されている
- [ ] ブリーフ生成で設計書本体（`docs/design/screens/` 等）が書き換えられていない
- [ ] Claude Design の Export 物が `docs/design/ui-design/handoff/` 配下に **Export 構造そのまま**（`README.md` / `prototype/` / `tokens/`）格納されている（画面単位 `[scr-id]/` には分割されていない）
- [ ] `docs/design/ui-design/handoff/README.md` に scr-id → prototype 関数のマッピング表がある
- [ ] ブランドガイドライン（あれば）と整合

### 3.4 実装コード（バックエンド）

- [ ] Controller が薄く、業務ロジックが Service に集約
- [ ] Repository が永続化アクセスを担い、JPA / Entity 設計が DB 定義と一致
- [ ] JWT 認証・CORS 設定が設計書の通り
- [ ] Bean Validation で入力検証が実装されている
- [ ] 例外ハンドリング（ControllerAdvice 等）が一貫している
- [ ] Checkstyle・PMD・SpotBugs に違反なし
- [ ] JaCoCo カバレッジが規定閾値以上、除外には理由コメント
- [ ] migration（Flyway/Liquibase）が追加され、Entity / DDL / `docs/design/tables/*.md` と整合

### 3.5 実装コード（フロントエンド）

- [ ] Presentational / Container 分離ができている
- [ ] API 呼び出しが `src/api/` 等のサービス層に集約
- [ ] Redux Toolkit / Zustand など状態管理の使い方が一貫
- [ ] React Router のルーティングが画面遷移図と一致
- [ ] ESLint / Prettier / TS 型チェックに違反なし
- [ ] Vitest / RTL のテストが各コンポーネント・各 AC に対応
- [ ] アクセシビリティの基本（label, role, alt）が満たされる

### 3.6 単体テスト（UT）

- [ ] AC-XXX または機能要件 ID と紐付くテスト名
- [ ] バックエンド: Service の業務ロジックを MockMvc / Mockito で検証
- [ ] フロントエンド: Container ロジックと Presentational 表示を分けてテスト
- [ ] 境界値・異常系・null/empty を含む
- [ ] カバレッジ閾値を満たす（除外は理由付き）

### 3.7 E2E テスト（Playwright）

- [ ] `docs/test/E2Eシナリオ.md` のシナリオ ID と一致
- [ ] 画面 ID ベースのナビゲーション
- [ ] テストデータ作成・後始末が完結
- [ ] CI 上で安定稼働（flaky 対策のリトライ・待機が適切）

### 3.8 Issue / PR

- [ ] タイトル規約: `[SCR-XXX] ...` / `[API] ...` / `[IF] ...` / `[TBL] ...` / `[BUG] ...`
- [ ] ラベル: `type:<種別>` と `status:<状態>`
- [ ] 関連設計書へのリンクが本文先頭
- [ ] AC がチェックボックス形式
- [ ] PR には関連 Issue 番号 / 影響範囲 / 確認手順
- [ ] CI green（UT / 静的解析 / E2E）

---

## 4. レビューの実施方法

### 4.1 自動レビュー（AI）

- `review-requirements` / `review-design` / `review-implementation` を該当フェーズの `*-loop` が呼び出す。
- 出力は `.skills-state/<phase>/round-<N>-review.json`。
- スキーマは [01-prompt-rules.md §2.3](01-prompt-rules.md#23-review-skill-出力jsonテンプレート) に準拠。

### 4.2 人手レビュー（必須ゲート）

人手レビューは AI レビューを **代替しない**。両者を直列に通す。

| ゲート | 何を確認するか |
|--------|----------------|
| **要件採択ゲート** | スコープ・優先順・open-questions の解決方針。AI が補完しなかった事業判断。 |
| **設計採択ゲート** | 標準スタック準拠・性能/セキュリティ要件・将来の拡張可能性。 |
| **PR レビューゲート** | 設計意図の反映・テストの十分性・運用観点・実コード品質。 |

人手レビュアは BLOCK / SUGGEST / NIT の重大度を引き継いで指摘する（Issue / PR コメントに `[BLOCK]` 等のラベルを付ける）。

### 4.3 役割分担

| 役割 | AI レビューでカバー | 人手レビューでカバー |
|------|---------------------|----------------------|
| 形式・網羅・整合の機械的チェック | ◎ | △（補助） |
| 事業判断・優先順・トレードオフ | △ | ◎ |
| 性能・運用上の現実的制約 | △ | ◎ |
| セキュリティの一次フィルタ | ◎ | ○ |
| セキュリティの最終確認 | × | ◎ |

---

## 5. ループ停止条件

| 条件 | 次の挙動 |
|------|----------|
| BLOCK = 0 | PASS。次フェーズへ進む（要件・設計はそのあと人手採択ゲート） |
| BLOCK > 0 かつ iteration < 3 | fix → review を再度実行 |
| BLOCK > 0 かつ iteration = 3 | **ESCALATE**。未解決 BLOCK 一覧を提示し、人手介入 |

> 出典: CLAUDE.md「改善ループ（Pattern 4）の終了条件」、`.claude/skills/_common/scripts/record-review.sh`。

### 5.1 ESCALATE 時の人手対応

1. `.skills-state/<phase>/state.json` と最新の `round-N-review.json` を読む。
2. 残存 BLOCK が **AI で解決すべきか / 事業判断が必要か** を切り分ける。
3. 後者なら `オープン課題.md` または Issue に転記し、関係者と合意する。
4. 合意後にフェーズを再起動するか、要件側を更新してやり直す。

---

## 6. ノウハウ集

### N-01: 「BLOCK は『次フェーズ阻害』で線を引く」

「気になる」「もう少し」は SUGGEST。実際に後工程が困るものだけを BLOCK にする。BLOCK の濫用は iteration を浪費し、ESCALATE が形骸化する。

### N-02: 「suggested_fix を必ず書かせる」

review skill の各 finding に修正案を含めると、fix skill の判断ロスが減り、収束が早い。

### N-03: 「review は fork、fix も fork」

produce の思考を引き継ぐと、判定が甘くなる / 修正範囲が膨らむ。両方とも fork して、入力ファイルだけを根拠にする。

### N-04: 「人手レビューは AI のラベルを継承」

人手指摘も `[BLOCK]` / `[SUGGEST]` / `[NIT]` を付けると、後工程の処理（誰が直すか、PR をブロックするか）が機械的に決まる。

### N-05: 「ESCALATE は失敗ではない」

3 回回しても BLOCK が残るのは、要件・設計のどこかに事業判断が残っているサイン。AI を責めず、人手判断のためのインプットとして使う。

### N-06: 「採択ゲートを skip しない」

要件・設計の採要件・設計の採択は人手の判断であり、AI に委ねない。レビューが軽くなりがちな
場合でも、CLAUDE.md「開発ルール」に明記された採択ゲートを必ず通す。
