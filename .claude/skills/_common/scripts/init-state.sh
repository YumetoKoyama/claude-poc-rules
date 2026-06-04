#!/usr/bin/env bash
# _common/scripts/init-state.sh
#
# 第1層（決定論）: skills 横断の state JSON を初期化する。
# 既存の state があれば上書きせず、現状を出力するだけ（冪等）。
#
# Usage:
#   init-state.sh <phase> [extra_args] [max_iterations]
#     <phase>          : requirements | design | implement
#     [extra_args]     : produce skill へ渡す追加引数（省略可）
#     [max_iterations] : 反復上限（省略時 3）
#
# 出力: state ファイルの絶対パスを stdout に 1 行で出す
#       （Claude 側でこのパスを Read して以降の判断に使う）

set -euo pipefail

PHASE="${1:-}"
EXTRA_ARGS="${2:-}"
MAX_ITER="${3:-3}"

if [[ -z "$PHASE" ]]; then
  echo "ERROR: phase が指定されていません" >&2
  exit 1
fi
case "$PHASE" in
  requirements|design|implement) ;;
  *) echo "ERROR: 未知の phase: $PHASE" >&2; exit 1 ;;
esac

STATE_DIR=".skills-state/${PHASE}"
STATE_FILE="${STATE_DIR}/state.json"
mkdir -p "$STATE_DIR"

# 既存があれば更新せずパスのみ返す（冪等）
if [[ -f "$STATE_FILE" ]]; then
  echo "$STATE_FILE"
  exit 0
fi

# 既存がない場合のみ初期化
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
case "$PHASE" in
  requirements) ARTIFACT_PATH="docs/requirements/" ;;
  design)       ARTIFACT_PATH="docs/design/"       ;;
  implement)    ARTIFACT_PATH="."                  ;;  # implement は branch / PR 全体が対象
esac

python3 - <<PY
import json
state = {
  "phase":           "$PHASE",
  "iteration":       1,
  "max_iterations":  int("$MAX_ITER"),
  "stage":           "produce",
  "artifact_path":   "$ARTIFACT_PATH",
  "extra_args":      "$EXTRA_ARGS",
  "last_review_path": None,
  "review_counts":   {"block": 0, "suggest": 0, "nit": 0},
  "passed":          False,
  "escalated":       False,
  "created_at":      "$NOW",
  "updated_at":      "$NOW",
  "history": [
    {"iteration": 1, "stage": "init", "completed_at": "$NOW"}
  ]
}
with open("$STATE_FILE", "w") as f:
  json.dump(state, f, ensure_ascii=False, indent=2)
PY

echo "$STATE_FILE"
