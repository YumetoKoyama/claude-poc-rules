#!/usr/bin/env bash
# _common/scripts/summarize-state.sh
#
# 第1層: state JSON を人間可読のサマリとして出力する。
# orchestrator skill の最終報告で使う。
#
# Usage:
#   summarize-state.sh <phase>

set -euo pipefail

PHASE="${1:-}"
# .skills-state の出力/参照先を phase から決定論的に解決（CWD 非依存・所有リポ集約）
# shellcheck source=_state-root.sh
source "$(dirname "${BASH_SOURCE[0]}")/_state-root.sh"
: "${STATE_ROOT:=$(resolve_state_root "$PHASE")}"
STATE_FILE="${STATE_ROOT:-.}/.skills-state/${PHASE}/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: state file not found: $STATE_FILE" >&2
  exit 1
fi

ST_FILE="$STATE_FILE" python3 - <<'PY'
import json, os
with open(os.environ["ST_FILE"], encoding="utf-8") as f:
  s = json.load(f)

print(f"## {s['phase']} loop サマリ")
print()
print(f"- 試行回数: {s['iteration']} / {s['max_iterations']}")
print(f"- 最終 stage: {s['stage']}")
print(f"- PASS: {s['passed']}")
print(f"- ESCALATED: {s['escalated']}")
rc = s.get("review_counts", {})
print(f"- 直近レビュー件数: BLOCK={rc.get('block',0)} / SUGGEST={rc.get('suggest',0)} / NIT={rc.get('nit',0)}")
if s.get("last_review_path"):
  print(f"- 最新 review JSON: {s['last_review_path']}")
print()
print("### 履歴")
for h in s.get("history", []):
  extra = ""
  if "block" in h:
    extra = f" (block={h['block']})"
  print(f"- iter={h['iteration']} stage={h['stage']}{extra} at {h['completed_at']}")
PY
