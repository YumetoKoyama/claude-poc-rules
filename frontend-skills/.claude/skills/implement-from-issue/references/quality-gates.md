# 品質ゲート詳細

## npm audit 判定スクリプト（cicd.yml の `npm-audit` ジョブと同一ロジック）

```bash
npm audit --json > audit.json 2>/dev/null || true
node -e "
  const fs = require('fs');
  const data = JSON.parse(fs.readFileSync('audit.json', 'utf8'));
  const vulnerabilities = Object.values(data.vulnerabilities || {});
  let found = 0;
  for (const v of vulnerabilities) {
    if (v.severity === 'critical' || v.severity === 'high') {
      const via = v.via.map(x => typeof x === 'string' ? x : x.title).join(', ');
      console.log('[' + v.severity.toUpperCase().padEnd(8) + '] ' + v.name + ' | ' + via);
      found++;
    }
  }
  if (found > 0) {
    console.error('critical または high の脆弱性が ' + found + ' 件検出されました。');
    process.exit(1);
  }
  console.log('critical / high の脆弱性は検出されませんでした。');
"
```

## レポート出力パス（固定）

後段の `review-implementation` がレポートを**コード内容ハッシュ**（`coverage/.gate-content`・backend と共通メカニズム）で「品質ゲートが現在のコードに対して実行されたか」を判定できるよう、各ゲートは次の固定パスにレポートを出力する（サイドカー出力は `implement-from-issue` 本体手順参照）。

| ゲート | 出力パス |
| --- | --- |
| 単体テスト + カバレッジ（Vitest / Istanbul） | `coverage/`（リポジトリルート直下） |
| ESLint | `eslint-report.json`（リポジトリルート直下） |
| npm audit | `audit.json`（リポジトリルート直下） |

## 品質ゲート一覧表とハッシュサイドカー（手順5・RC-07）

implement-from-issue（frontend-skills 系統）手順5から 2026-07-02 に PP-5 分解で外出し。本文の該当手順から参照される。

| 品質ゲート | 内容 | コマンド（cicd.yml 準拠） | 参照する補助 skill |
| --- | --- | --- | --- |
| 単体テスト + カバレッジ | Vitest + React Testing Library。閾値: **分岐 90% 以上・命令（ライン/ステートメント）100%**（除外後。`vitest.config.ts` の threshold 設定に従う） | `npx vitest run --coverage` | `/unit-test-from-design` |
| ESLint | 警告 0 件。レポートを `eslint-report.json` に出力 | `npx eslint . --format json --output-file eslint-report.json --max-warnings=0` | `/static-analysis-remediation` |
| Prettier | フォーマット差分 0 件（修正は行わず検査のみ） | `npx prettier --check .` | `/static-analysis-remediation` |
| npm audit | `critical` / `high` の脆弱性 0 件 | `npm audit --json > audit.json && node -e "..."` ※後述 | — |
| セキュリティレビュー | OWASP ベースの自己点検（認可バイパス・JWT 検証・機密情報のログ/レスポンス漏えい・入力サニタイズ）。PR 作成前に必須 | — | `docs/design/セキュリティテスト観点.md` |

> npm audit の判定スクリプトと各ゲートのレポート出力パスは [references/quality-gates.md](references/quality-gates.md) を参照。

<!-- rules 改善（RC-07・収束不能バグ修正）: 品質ゲートに「コード内容ハッシュ」を併記（review 側の内容照合とペア・backend と共通メカニズム） -->
#### 品質ゲートのレポート出力とハッシュサイドカー（RC-07・review との対）

後段の `review-implementation` が「品質ゲートが現在のコードに対して実行されたか」を **コード内容** で照合できるよう、各ゲート実行直後に **コード内容ハッシュ** をサイドカーへ残す（時刻・コミットハッシュ依存を廃止。FE は `coverage/` 配下・backend と同一メカニズム）。

> **なぜコミットハッシュではないか**: 旧方式（`git rev-parse HEAD` を `coverage/.gate-commit` に保存し現 HEAD と照合）は、ゲート実行後の fix コミットや `docs(review)` コミットで HEAD が進むたびに不一致になり、「gate-commit == HEAD」が原理的に成立しなかった。結果、improve ループが収束せず常に max_iterations を消化して escalate していた。コード内容ハッシュは docs 専用・レビュー結果コミット等（コードを変えない変更）では変化しないため、この誤検知を解消する。

```bash
# ゲート実行直後にコード内容ハッシュをサイドカーへ残す（backend と共通メカニズム）
mkdir -p coverage
bash .claude/skills/_common/scripts/gate-content-hash.sh > coverage/.gate-content    # FE
```

review-implementation は `gate-content-hash.sh` を **再計算** して `coverage/.gate-content` と照合し、**不一致・不在なら category=`quality_gate`**（現コードでゲート未実行）とする。`.gate-content` が存在しない移行期のレポートに限り、従来の `.gate-commit` / レポート更新時刻でフォールバック判定してよい。固定出力パス: 単体テスト + カバレッジ＝`coverage/`（Istanbul）、ESLint＝`eslint-report.json`、型チェック＝実行ログ。CI は子リポジトリ単体チェックアウトのため `frontend/` 接頭辞は付かない（own リポジトリのルート起点）。
## テスト実行が遅い環境での対処（RC-10・サンドボックス/CI）

2026-07-02 の `/implement-loop` 実行（3h12m）で、コンテナ内の Vitest が forks worker の起動失敗（`Failed to start forks worker`）により `--no-file-parallelism`（完全直列）へフォールバックし、フル品質ゲート 1 回に 20〜30 分かかる事象が発生した（produce + fix で全体の 8 割超を消費）。同事象への対処順序:

1. **直列フォールバックの前に worker 設定を切り替える**: `Failed to start forks worker` が出た場合、まず `npx vitest run --coverage --pool=threads` を試す（forks はプロセス fork、threads は worker_threads であり、メモリ/プロセス数制約のあるコンテナでは threads が起動できることが多い）。必要なら `--maxWorkers=2` 等で並列度を明示的に絞る。
2. **`--no-file-parallelism`（完全直列）は最終手段**とし、使った場合は stdout にその旨と所要時間を明記する（環境問題として ESCALATE 対象の判断材料にする）。
3. **恒久対応は `vitest.config.ts` 側で行う**（正典は frontend リポジトリ）。推奨設定例:

```typescript
// vitest.config.ts（抜粋）: コンテナ等プロセス数制約環境向けフォールバック
export default defineConfig({
  test: {
    pool: process.env.VITEST_POOL ?? 'forks',   // CI/サンドボックスでは VITEST_POOL=threads を指定
    poolOptions: {
      threads: { maxThreads: 4, minThreads: 1 },
      forks: { maxForks: 4, minForks: 1 },
    },
  },
});
```

4. **バックグラウンド化で「速く見せる」ことは禁止（RC-09）**: 遅くても同期実行で完了を待つ。forked skill 内のバックグラウンド起動は fork 終了とともにプロセスが死に、レポート未生成事故（fix 空振り・約30分ロス）の直接原因になった。
