#!/usr/bin/env bash
# _common/scripts/advance-state.sh
#
# 第1層: stage を次に進める。fix → review への遷移時は iteration++ する。
# エスカレーション判定は行わない（record-review.sh に一元化）。
#
# Usage:
#   advance-state.sh <phase> <next_stage>
#     <next_stage> : produce | review | fix | done | escalate

set -euo pipefail

PHASE="${1:-}"
NEXT_STAGE="${2:-}"

STATE_FILE=".skills-state/${PHASE}/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: state file not found: $STATE_FILE" >&2
  exit 1
fi

python3 - <<PY
import json, datetime
p = "$STATE_FILE"
with open(p) as f:
  s = json.load(f)
now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

prev_stage = s["stage"]
next_stage = "$NEXT_STAGE"

# 履歴記録
s["history"].append({
  "iteration": s["iteration"],
  "stage": prev_stage,
  "completed_at": now,
})

# fix → review の遷移時は iteration をインクリメント
if prev_stage == "fix" and next_stage == "review":
  s["iteration"] += 1

# エスカレーション判定は record-review.sh に一元化している（ここでは行わない）。
# advance-state.sh は stage 遷移と iteration++ のみを担当する。

# 終端ステージ
if next_stage == "done":
  s["passed"] = True

s["stage"] = next_stage
s["updated_at"] = now

with open(p, "w") as f:
  json.dump(s, f, ensure_ascii=False, indent=2)

print(f"phase={s['phase']} stage={s['stage']} iteration={s['iteration']}")
PY
