# 品質ゲート詳細（Pattern 2 並列ファンアウト・レポート出力パス）

implement-from-issue 本文から 2026-07-02 に PP-5 分解で外出し。本文の該当手順から参照される。

| 品質ゲート | 内容 | 参照する補助 skill |
| --- | --- | --- |
| 単体テスト | バックエンド: JUnit5 + Mockito + MockMvc / フロントエンド: Vitest（または Jest）+ React Testing Library（カバレッジ閾値は各確定表: BE `backend-00-stack.md` #13 = 命令100%/分岐90%・FE `frontend-00-stack.md` #10 = 100%、いずれも除外後） | `/unit-test-from-design` |
| 静的解析 | バックエンド: SpotBugs / Checkstyle / PMD / フロントエンド: ESLint / Prettier / TypeScript 型チェック | `/static-analysis-remediation` |
| セキュリティレビュー | OWASP ベースの自己点検（認可バイパス・IDOR/テナント越境・JWT 検証・機密情報のログ/レスポンス出力・入力サニタイズ）。PR 作成前に必須 | `docs/design/セキュリティテスト観点.md` |

- **E2E は本スキルでは実行しない**（AWS 環境構築後に E2E リポジトリの別工程として実施。`/e2e-from-design` は凍結中で呼び出さない）。
- **結合テスト（IT-XXX）も本スキルでは設計・実施しない**。結合テストはフィーチャ単位で複数 Issue をまたぐため、設計・実施とも **結合テスト工程**（`/integration-test-from-design`）で行う（E2E と同様の切り分け）。
- カバレッジが確定表の閾値（BE #13 命令100%/分岐90% ・ FE #10 100%、いずれも除外後）に届かない場合は `/coverage-to-100` の手順で不足分を補う。
- すべてのゲートが成功するまで次のステップへ進まない。
- 失敗時は原因（アプリ側 / テスト側 / 環境）を切り分けて修正し、同じゲートを再実行する。新しい teammate は起動しない。
- 変更が非機能要件（性能・負荷・可用性）に関わる場合は `docs/design/非機能テスト計画.md` の該当検証を実施し結果を記録する。実装した AC-XXX と **TC-XXX** の対応は own リポジトリの `docs/test/トレーサビリティマトリクス.md`（RTM）に反映する（IT/E2E 列は各別工程が記入）。
- **同一 Issue 内で閉じる最小 IT を必須化（RC-07）**: 当該 Issue の範囲で閉じる **トランザクション境界・例外ロールバック整合** の最小結合テスト（例: Service の `@Transactional` メソッドで例外発生時にロールバックされる／コミットされる）を品質ゲートに含めて実施する。**複数 Issue をまたぐ結合（契約スモーク含む）は本スキルでは行わず**、結合テスト工程（`/integration-test-from-design`）に委ねる。契約スモーク（ログイン→主要画面データ取得を実 HTTP で疎通）は integration-test-from-design 側で実施する。

#### 品質ゲートのレポート出力パス（固定）

後段の `review-implementation` がレポートを **内容（対象コミット/ファイルハッシュ）** で照合して「品質ゲートが現在のコードに対して実行されたか」を判定できるよう（RC-07・時刻依存は廃止）、各ゲートは次の固定パスにレポートを出力し、**各レポートと同じ位置に対象ハッシュを併記する**。ゲート実行直後に次を記録する:

```bash
# 例: ゲート実行時の HEAD と対象差分ファイルのハッシュをサイドカーに残す
mkdir -p target coverage
git rev-parse HEAD > target/.gate-commit       # BE
git rev-parse HEAD > coverage/.gate-commit      # FE
git diff --name-only main...HEAD | xargs -r sha1sum > target/.gate-files 2>/dev/null || true
```

review-implementation は `target/.gate-commit` / `coverage/.gate-commit` を現 HEAD と照合し、不一致・不在なら BLOCK とする。固定出力パスは次のとおり。

| ゲート | 出力パス |
| --- | --- |
| バックエンド単体テスト | `target/surefire-reports/` |
| バックエンドカバレッジ（JaCoCo） | `target/site/jacoco/jacoco.xml` |
| バックエンド静的解析 | `target/`（SpotBugs / Checkstyle / PMD の各レポート） |
| フロントエンド単体テスト + カバレッジ | `coverage/`（Istanbul） |
| フロントエンド静的解析 | `eslint-report.json`（ESLint）/ 型チェックは実行ログ |

> 上表は own リポジトリのルートを起点とする（CI は子リポジトリ単体チェックアウトのため `backend/` `frontend/` の接頭辞は付かない）。モジュール構成が異なる場合は実際のモジュールルートに読み替え、出力先を本 skill の実行ログに明記する。
