# 横断 AI ルール（CI 必須の共有正典）

本リポジトリ（claude-poc-rules）は 6 リポジトリ構成の親（アンブレラ）であり、本ファイルは全リポジトリ横断のルールの正典である。

> **CI 到達性（RC-13・最重要）**: CI は子リポジトリ＋`claude-poc-docs` のみをチェックアウトし、親 `claude-poc-rules` の CLAUDE.md・`rules/` を**持ち込まない**。したがって本ファイルは「親に置いておくだけ」では CI（implement / fix / review / test）に届かない。本ファイルは**各子リポジトリの `.claude/rules/cross-cutting.md` へ同期配布**して初めて CI 上で有効になる（手コピー禁止・symlink / サブモジュール / CI 同期。同期検査は `_common/scripts/check-claude-md-sync.sh`）。子リポ単体チェックアウトでも本ルールが効くこと（親非依存で成立）が満たすべき不変条件である。
>
> 親 CLAUDE.md 単独に書いた CI 必須ルールは無効。CI で走るフェーズに効かせるルールは、スキル本文・子 `.claude/rules/`・`_common/scripts/`（＝子へ配布され CI に存在する成果物）に置く。

## 正典の二層構成

| 正典 | 置き場所 | 内容 | CI 到達 |
|---|---|---|---|
| 開発フロー（人間向け索引・ローカル専用オーケストレーション） | 親 CLAUDE.md | フェーズ順序・採択ゲート（ローカル起動時のマージ済み確認等） | 親のみ（CI 非到達） |
| 横断 AI ルール（CI 必須の共有正典） | 親 rules/cross-cutting.md → 各子 .claude/rules/cross-cutting.md へ配布 | ID/命名・テスト 3 層/RTM・セキュリティ観点・界面契約・並行制御・data-sufficiency・正典保護 | 配布で子に到達 |
| 共有正典ブロック（shared-canon） | 親 CLAUDE.md の `<!-- shared-canon -->` → 各子 CLAUDE.md へ自動生成 | 上記の最小規約を子 CLAUDE.md にも埋め込み二重化 | 配布で子に到達 |
| フロントエンド技術ルール | claude-poc-frontend/.claude/rules/frontend-*.md | FW・構成・状態管理・テスト規約（矛盾時の最優先＝正） | 子に常駐 |
| バックエンド技術ルール | claude-poc-backend/.claude/rules/backend-*.md | アーキテクチャ・レイヤー・スタック確定値（ddl-auto 免除の解除条件＝#8 を含む） | 子に常駐 |
| バッチ／E2E 技術ルール | claude-poc-batch / claude-poc-e2e の .claude/rules/ | バッチ実装規約・E2E（凍結中）。整備は人間 | 子に常駐 |

- 技術スタックの確定値は**各子の `.claude/rules/` にのみ**記載する（親 CLAUDE.md・設計書・スキルは再掲せず参照する）。
- 親から起動したセッション・スキルは、子の rules を自動読み込みできないため、**対象リポジトリの `.claude/rules/` を必ず Read してから作業する**。

## CI 必須の共有正典（子へ配布される最小規約）

> 本章は親 CLAUDE.md の `shared-canon` ブロックと**同一内容**であり、子 `.claude/rules/cross-cutting.md` へ配布される前提で記述する。矛盾時は frontend ルール（FE 内部実装規約に限る）と本章（界面契約・横断規約）で役割を分け、界面契約は設計書を正とする。

### 1. ID・採番・凡例規約

- ID は「英字プレフィックス + 3 桁ゼロ埋め連番」。主な体系: `SCR- / UC- / ACT- / AC- / BR- / ENT- / ST- / EXT- / MIG- / MSG- / SEQ- / TC- / IT- / E2E-`。
- 要件・設計・テストで**同じ ID を引用**して縦串トレースを成立させる。
- ID・略号を導入する文書は冒頭付近に**凡例（略号一覧表）を必ず置き**、新規略号追加時に凡例も更新する。

### 2. テスト 3 層と RTM

- テストは **単体（TC）/ 結合（IT）/ E2E** の 3 層。各テストは **正常系 / 異常系 / 境界値 / 権限境界** の区分を明示する。
- AC-XXX ごとに少なくとも 1 つの実行可能テストを対応づける。
- RTM（トレーサビリティマトリクス）に UC / AC / BR / SCR / API operationId / Issue# / TC / IT / E2E を 1 表で集約。単体(TC)・RTM は製造、結合(IT) は結合テスト工程の成果物。

### 3. セキュリティレビュー観点（OWASP ベース）

- 認可バイパス・IDOR / テナント越境・JWT 改ざん・機微情報のレスポンス/ログ漏えい・入力サニタイズを必須観点とする。
- **テナントフィルタは SELECT / UPDATE / DELETE / COUNT / 集計クエリのすべてに適用**する。
- **テナント越境は 404、自テナント内の権限不足は 403** に統一する。
- 認可は `@PreAuthorize`（BE）に集約し、各 operationId の必要ロールが認可設計と一致することを突合する。

### 4. 界面契約の単一正典（`_common.yaml`）

- API / エラー / コード値の界面契約の正典は `docs/design/api/_common.yaml`。実装・FE はこれを参照し、JSON 上の実フィールド名（`code` / `details[].reason` 等）を一字一句一致させる。
- コード値（enum）は **4 層で統一**: 要件 `コード値定義.md` → 設計 `_common.yaml` → BE enum → FE const。

### 5. 並行制御（必須）

- 状態遷移を持つ集約（ステータス・カウンタ・先着・上限）は、並行制御方針（楽観 `@Version` / 悲観 `FOR UPDATE`）と DB 一意制約を必ず明記する。
- 「先着」「上限 N」「二重不可」は DB 一意制約／条件付き UPDATE／行ロックで保証する（非正規化カウンタ単独での上限判定を禁止）。

### 6. data-sufficiency（画面表示項目 ↔ API 対応）

- 画面で「表示する」全データ項目・業務判定値は、供給元 API（operationId × レスポンスフィールド）が存在し、画面 md の API 欄に取得経路が明示されていること。供給元不在は設計の BLOCK。
- パス変数・クエリパラメータの値の出所（前画面項目・レスポンスフィールド）が画面遷移・シーケンスに現れること。

### 7. オープン課題のクローズ規約

- `Q-NF* / Q-DM* / Q-EI* / Q-MIG*` は設計フェーズ起動前に closed にする（要件採択者の責務）。`オープン課題.md` 冒頭にクローズ運用ルール章を置く。

## 採択ゲート（人間の明示アクション）

- **要件定義・設計書の採択 = docs リポジトリ（claude-poc-docs）の `main` への PR マージ**。人間のレビュー・マージが採択行為であり、PR が証跡となる（前提: docs の `main` に branch protection）。
- **実装の開始 = 人間が対象 Issue に `@claude` とコメントすること**。Claude・skill が自らコメント・マージして起動してはならない。
- ローカル起動時は、入力ドキュメントが docs の `main` にマージ済みであることを確認し、未マージなら中断して人手レビュー・マージを依頼する。

## state とオーケストレーションの不変条件（RC-08）

- `.skills-state/<phase>/state.json` は `init-state.sh` / `advance-state.sh` / `record-review.sh` のスクリプト経由でのみ更新する（**手編集禁止**）。
- iteration ≤ max_iterations を `advance-state.sh` のガードで保証し、超過時は escalate へ遷移する。state 不在のままの review は無効。

## 正典の保護

- 親 `rules/`・各子の `.claude/rules/`・リポジトリ直下の `CLAUDE.md` は Claude 実行中の編集を禁止する（`.claude/hooks/protect-canon.sh`。D-07 で保護対象を正典限定に絞り、業務コード中の任意階層 `.../rules/` は巻き込まない）。
- 変更は人手で行う。Claude に依頼する場合のみ `ALLOW_RULES_EDIT=1` のセッションで行う。
- スキルの自動実行はフラグを立てないため常にブロックされ、ルール書き換えで品質ゲートは通せない。

## CI/CD セキュリティ（RC-12）

- `@claude` 自動修正系ワークフロー（`claude-fix-*`）は `author_association ∈ {OWNER, MEMBER, COLLABORATOR}` で発火制限し、Bash 許可・PAT scope を最小化する。`pull_request_target` は原則回避（必要時は信頼境界を併用）。
- 自動 Issue 起票ワークフローは `MEMBER` 以上に限定する。これらは CI 雛形として子へ配布する。
