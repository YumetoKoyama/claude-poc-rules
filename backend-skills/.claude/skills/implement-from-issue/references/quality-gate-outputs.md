# 品質ゲートのレポート出力パス

<!-- 2026-07-02 再生成: 末尾切断(D-1)を復元し、判定方式の記述を RC-07（内容ハッシュ照合）の現行配線に合わせて更新 -->

後段の `review-implementation` が「品質ゲートが**現在のコード**に対して実際に実行されたか」を判定するため、各ゲートは以下の固定パスにレポートを出力する。判定は **コード内容ハッシュの照合（RC-07）** で行う: ゲート実行直後に `gate-content-hash.sh` の出力をサイドカーへ保存し、review 側が再計算して照合する（`.gate-content` が無い移行期のレポートに限り、従来の `.gate-commit` / 更新時刻でフォールバック判定してよい）。

| ゲート | 出力パス |
| --- | --- |
| バックエンド単体テスト | `target/surefire-reports/` |
| バックエンドカバレッジ（JaCoCo） | `target/site/jacoco/jacoco.xml` |
| バックエンド静的解析 | `target/`（SpotBugs / Checkstyle / PMD の各レポート） |
| フロントエンド単体テスト + カバレッジ | `coverage/`（Istanbul） |
| フロントエンド静的解析 | `eslint-report.json`（ESLint）/ 型チェックは実行ログ |
| **ハッシュサイドカー（RC-07）** | `target/.gate-content`（BE。FE 同居時は `coverage/.gate-content` にもコピー） |

> 上表は own リポジトリのルートを起点とする（CI は子リポジトリ単体チェックアウトのため `backend/` `frontend/` の接頭辞は付かない）。モジュール構成が異なる場合は実際のモジュールルートに読み替え、読み替えた出力先を本 skill の実行ログに明記する（review 側が場所を特定できるようにする）。

## ハッシュサイドカーの出力手順（手順5・RC-07）

implement-from-issue（backend-skills 系統）手順5から 2026-07-02 に PP-5 分解で外出し。本文の該当手順から参照される。

**ハッシュサイドカーの出力（RC-07・収束不能バグ修正）**: 後段の `review-implementation` が「品質ゲートが現在のコードに対して実行されたか」を**コード内容**で照合できるよう、ゲート実行直後に**コード内容ハッシュ**をサイドカーへ残す。

> **なぜコミットハッシュではないか**: 旧方式（`git rev-parse HEAD` を `.gate-commit` に保存し現 HEAD と照合）は、ゲート実行後の fix コミットや `docs(review)` コミットで HEAD が進むたびに不一致になり、「gate-commit == HEAD」が原理的に成立しなかった。結果、improve ループが収束せず常に max_iterations を消化して escalate していた。コード内容ハッシュは docs 専用・レビュー結果コミット等（コードを変えない変更）では変化しないため、この誤検知を解消する。

```bash
mkdir -p target coverage
bash .claude/skills/_common/scripts/gate-content-hash.sh > target/.gate-content    # BE
cp target/.gate-content coverage/.gate-content 2>/dev/null || true                 # FE（FE 同居時）
```

review-implementation は `gate-content-hash.sh` を**再計算**して `target/.gate-content` と照合し、**不一致・不在なら category=`quality_gate`**（現コードでゲート未実行）とする。`.gate-content` が存在しない移行期のレポートに限り、従来の `.gate-commit` / レポート更新時刻でフォールバック判定してよい。
