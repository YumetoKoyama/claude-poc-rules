#!/usr/bin/env bash
# _common/scripts/gate-content-hash.sh
#
# 役割（RC-07 改善 / 収束不能バグ修正・backend と共通メカニズム）:
#   品質ゲート（単体テスト・型チェック・静的解析）が「現在のコード」に対して
#   実行されたかを判定するための、コード内容ベースの安定ハッシュを算出する。
#   コミットハッシュ方式（旧 .gate-commit）は fix/docs(review) コミットで HEAD が
#   進むたびに無効化され収束しなかったため、コード内容で判定する。
#   ※ 算出アルゴリズム（allowlist 差分ファイルの sha256 を連結して再 sha256）は
#     backend の gate-content-hash.sh と同一。対象 allowlist のみ FE スタックに調整。
#
# 対象は「品質ゲートが検証するアプリのコード」のみ（allowlist）:
#   src/                                本体・テスト（*.test.ts(x) 隣接配置）・リソース
#   package.json / package-lock.json    依存・ビルド定義
#   tsconfig*.json                      型チェック設定
#   eslint.config.* / .eslintrc*        ESLint 設定
#   .prettierrc* / .prettierignore / prettier.config.*   Prettier 設定
#   vitest.config.* / vite.config.*     テストランナー設定
#   next.config.*                       ビルド設定
# docs/・.claude/・.github/・.skills-state/・coverage/ 等のインフラ/ドキュメント
# /ビルド生成物（tsconfig.tsbuildinfo 等）は含めない。
# （git のパスクオートでフィルタが破られないよう -z + core.quotepath=false を使う）
#
# 出力: sha256 1行 / コード差分なし=NO_CODE_CHANGE / git外=NO_GIT
# 比較ブランチは GATE_BASE_REF（既定 main）。
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "NO_GIT"; exit 0; }
cd "$ROOT"
BASE="${GATE_BASE_REF:-main}"
ALLOW='^(src/|package\.json$|package-lock\.json$|tsconfig[^/]*\.json$|eslint\.config\.[cm]?[jt]s$|\.eslintrc|\.prettierrc|\.prettierignore$|prettier\.config\.|vitest\.config\.|vite\.config\.|next\.config\.)'

FILES="$(
  {
    git -c core.quotepath=false diff -z --name-only "${BASE}...HEAD" 2>/dev/null || true
    git -c core.quotepath=false diff -z --name-only HEAD 2>/dev/null || true
    git -c core.quotepath=false diff -z --name-only --cached 2>/dev/null || true
  } | tr "\0" "\n" | LC_ALL=C sort -u | grep -E "$ALLOW" || true
)"

if [ -z "$FILES" ]; then
  echo "NO_CODE_CHANGE"
  exit 0
fi

while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [ -f "$f" ]; then
    printf "%s:" "$f"; sha256sum "$f" | awk "{print \$1}"
  else
    printf "%s:DELETED\n" "$f"
  fi
done <<< "$FILES" | sha256sum | awk "{print \$1}"
