#!/usr/bin/env bash
# _common/scripts/record-review.sh
#
# 第1層: review skill が生成した review JSON を state に取り込む。
# BLOCK 件数を見て passed=true か stage=fix か escalate を判定する（決定論）。
#
# ※ エスカレーション判定は本スクリプトに一元化している。advance-state.sh は
#   stage 遷移と iteration++ のみを担当し、escalate 判定は行わない。
#
# Usage:
#   record-review.sh <phase> <review_json_path>

set -euo pipefail

PHASE="${1:-}"
REVIEW_JSON="${2:-}"

STATE_FILE=".skills-state/${PHASE}/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: state file not found: $STATE_FILE" >&2
  exit 1
fi
if [[ ! -f "$REVIEW_JSON" ]]; then
  echo "ERROR: review JSON not found: $REVIEW_JSON" >&2
  exit 1
fi

python3 - "$STATE_FILE" "$REVIEW_JSON" <<'PY'
import json, datetime, os, sys
sp = sys.argv[1]
rp_in = sys.argv[2]
with open(sp) as f:
  s = json.load(f)
with open(rp_in) as f:
  r = json.load(f)

# review JSON のパスをリポジトリルート相対に正規化する（/workspace 等の絶対パス混入を防ぐ）
if ".skills-state/" in rp_in:
  rp = rp_in[rp_in.index(".skills-state/"):]
else:
  try:
    rp = os.path.relpath(os.path.abspath(rp_in), os.getcwd())
  except ValueError:
    rp = rp_in

counts = {"block": 0, "suggest": 0, "nit": 0}
for x in r.get("findings", []):
  sev = (x.get("severity") or "").upper()
  if sev == "BLOCK":
    counts["block"] += 1
  elif sev == "SUGGEST":
    counts["suggest"] += 1
  elif sev == "NIT":
    counts["nit"] += 1

now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
s["last_review_path"] = rp
s["review_counts"] = counts
s["updated_at"] = now

# review 完了イベントを history に必ず記録する（block 件数つき）
s.setdefault("history", []).append({
  "iteration": s["iteration"],
  "stage": "review",
  "block": counts["block"],
  "suggest": counts["suggest"],
  "nit": counts["nit"],
  "completed_at": now,
})

# 終了条件（エスカレーション判定はここに一元化）
if counts["block"] == 0:
  # BLOCK 0 件なら PASS
  s["passed"] = True
  s["stage"] = "done"
  s["history"].append({"iteration": s["iteration"], "stage": "done", "completed_at": now})
else:
  # BLOCK が残っており、iteration が上限に達しているなら escalate
  if s["iteration"] >= s["max_iterations"]:
    s["escalated"] = True
    s["stage"] = "escalate"
    s["history"].append({"iteration": s["iteration"], "stage": "escalate", "completed_at": now})
  else:
    s["stage"] = "fix"

with open(sp, "w") as f:
  json.dump(s, f, ensure_ascii=False, indent=2)

print(f"block={counts['block']} suggest={counts['suggest']} nit={counts['nit']} next_stage={s['stage']}")
PY
