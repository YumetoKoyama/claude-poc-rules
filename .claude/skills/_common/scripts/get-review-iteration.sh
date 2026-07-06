#!/usr/bin/env bash
# _common/scripts/get-review-iteration.sh
#
# review skill 向け: state.json から iteration のみを stdout に出力する。
# review skill が state.json を直接 Read することを避け、
# review_counts / history / max_iterations 等の情報漏洩を防ぐ。
#
# Usage:
#   get-review-iteration.sh <phase>
#   → stdout に iteration（整数）を 1 行出力
#
# Example:
#   N=$(bash .claude/skills/_common/scripts/get-review-iteration.sh requirements)
#   echo "round-${N}-review.json"

set -euo pipefail

PHASE="${1:-}"
if [[ -z "$PHASE" ]]; then
  echo "Usage: get-review-iteration.sh <phase>" >&2
  exit 1
fi

# .skills-state の出力/参照先を phase から決定論的に解決（CWD 非依存・所有リポ集約）
# shellcheck source=_state-root.sh
source "$(dirname "${BASH_SOURCE[0]}")/_state-root.sh"
: "${STATE_ROOT:=$(resolve_state_root "$PHASE")}"
STATE_FILE="${STATE_ROOT:-.}/.skills-state/${PHASE}/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: state file not found: $STATE_FILE" >&2
  exit 1
fi

python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f)['iteration'])
" "$STATE_FILE"
