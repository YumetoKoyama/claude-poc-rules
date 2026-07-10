#!/usr/bin/env bash
# _common/scripts/init-state-with-dispatch.sh
#
# implement-loop / integration-test-loop 専用ラッパー。
# 親アンブレラ（claude-poc-rules）から "<repo> <issue...>" の2引数形式で
# 呼ばれた場合に、対象子リポジトリのディレクトリへ cd してから init-state.sh を
# 実行する（state.json を正しいリポジトリ配下に生成するため）。
#
# 呼び出し元（implement-loop / integration-test-loop の SKILL.md）は、
# 標準出力の1行目 `DISPATCH_REPO_DIR=<dir または 空>` を見て、
# 空でなければ自分自身（Bash ツール）でも同じディレクトリへ cd し、
# 残りの引数（Issue番号等）だけで本スキルを呼び直す必要がある
# （本スクリプトの cd はこのスクリプト内のサブシェルにしか効かず、
#  以降の Claude 自身の操作には影響しないため）。
#
# Usage:
#   init-state-with-dispatch.sh <phase> <raw-arguments...>
#     <raw-arguments...>: $ARGUMENTS を単語分割したもの。
#       先頭が既知のリポジトリ略称（frontend/backend/batch/e2e）かつ
#       対応するディレクトリがカレント直下に存在する場合のみディスパッチする。
#       それ以外（略称が無い・単一引数・ディレクトリ不在）は
#       全引数をそのまま extra_args として init-state.sh に渡す（従来動作）。
#
# 出力:
#   1行目: DISPATCH_REPO_DIR=<dir>  （ディスパッチした場合のみ dir を記載）
#   2行目以降: init-state.sh の出力（state ファイルの絶対パス）

set -euo pipefail

PHASE="${1:-}"
shift || true
RAW_ARGS=("$@")

if [[ -z "$PHASE" ]]; then
  echo "ERROR: phase が指定されていません" >&2
  exit 1
fi

declare -A REPO_MAP=(
  [frontend]="claude-poc-frontend"
  [backend]="claude-poc-backend"
  [batch]="claude-poc-batch"
  [e2e]="claude-poc-e2e"
)

DISPATCH_DIR=""
REMAIN=("${RAW_ARGS[@]}")

if [[ ${#RAW_ARGS[@]} -ge 2 ]]; then
  first="${RAW_ARGS[0]}"
  candidate="${REPO_MAP[$first]:-}"
  if [[ -n "$candidate" && -d "$candidate" ]]; then
    DISPATCH_DIR="$candidate"
    REMAIN=("${RAW_ARGS[@]:1}")
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "$DISPATCH_DIR" ]]; then
  echo "DISPATCH_REPO_DIR=$DISPATCH_DIR"
  ( cd "$DISPATCH_DIR" && bash "$SCRIPT_DIR/init-state.sh" "$PHASE" "${REMAIN[@]}" )
else
  echo "DISPATCH_REPO_DIR="
  bash "$SCRIPT_DIR/init-state.sh" "$PHASE" "${REMAIN[@]}"
fi
