#!/usr/bin/env bash
# _common/scripts/advance-state.sh
#
# 第1層: stage を次に進める。fix → review への遷移時は iteration++ する。
#
# RC-08 強化:
#   - state スキーマ検証（必須キー: phase / created_at / iteration / max_iterations / history / stage）
#   - max_iterations 超過ガード: iteration が上限を超える状況では escalate へ倒す
#   - datetime.utcnow() → datetime.now(datetime.UTC)（非推奨 API の解消）
#   - phase は requirements | design | implement | integration | overall を許容
#
# Usage:
#   advance-state.sh <phase> <next_stage>
#     <phase>      : requirements | design | implement | integration | overall
#     <next_stage> : produce | review | fix | done | escalate

set -euo pipefail

PHASE="${1:-}"
NEXT_STAGE="${2:-}"

if [[ -z "$PHASE" || -z "$NEXT_STAGE" ]]; then
  echo "ERROR: usage: advance-state.sh <phase> <next_stage>" >&2
  exit 1
fi

case "$PHASE" in
  requirements|design|implement|integration|overall) ;;
  *) echo "ERROR: 未知の phase: $PHASE（requirements|design|implement|integration|overall）" >&2; exit 1 ;;
esac

case "$NEXT_STAGE" in
  test-design|test-write|produce|augment|review|fix|done|escalate) ;;
  *) echo "ERROR: 未知の next_stage: $NEXT_STAGE（test-design|test-write|produce|augment|review|fix|done|escalate）" >&2; exit 1 ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません（state を安全に更新できません）" >&2
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

python3 - "$STATE_FILE" "$NEXT_STAGE" <<'PY'
import json, datetime, sys, os, tempfile

def dump_atomic(obj, path):
  """D-08: 途中切断による不正 JSON を防ぐ（tmp へ書き fsync 後 rename）"""
  d = os.path.dirname(os.path.abspath(path)) or "."
  fd, tmp = tempfile.mkstemp(dir=d, prefix=".state-", suffix=".tmp")
  try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
      json.dump(obj, f, ensure_ascii=False, indent=2)
      f.flush()
      os.fsync(f.fileno())
    os.replace(tmp, path)
  except BaseException:
    try: os.unlink(tmp)
    except OSError: pass
    raise


p = sys.argv[1]
next_stage = sys.argv[2]

with open(p, encoding="utf-8") as f:
    s = json.load(f)

# --- state スキーマ検証（RC-08）---
REQUIRED = ("phase", "created_at", "iteration", "max_iterations", "history", "stage")
missing = [k for k in REQUIRED if k not in s]
if missing:
    print(f"ERROR: state スキーマ違反。必須キー欠落: {missing}", file=sys.stderr)
    sys.exit(1)
if not isinstance(s["history"], list):
    print("ERROR: state.history が配列ではありません", file=sys.stderr)
    sys.exit(1)
if not isinstance(s["iteration"], int) or not isinstance(s["max_iterations"], int):
    print("ERROR: iteration / max_iterations が整数ではありません", file=sys.stderr)
    sys.exit(1)

# UTC（datetime.utcnow() は非推奨。timezone-aware な now(timezone.utc) を使う。
# datetime.UTC は 3.11+ のエイリアスのため、互換のため timezone.utc を用いる）
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

prev_stage = s["stage"]

# 履歴記録
s["history"].append({
    "iteration": s["iteration"],
    "stage": prev_stage,
    "completed_at": now,
})

# fix → review の遷移時は iteration をインクリメント
if prev_stage == "fix" and next_stage == "review":
    s["iteration"] += 1

# --- max_iterations 超過ガード（RC-08）---
# 注（M-1）: ESCALATE 判定の一次権限は record-review.sh（iteration>=max かつ未充足で escalate）。
# 本ガードは「fix→review で iteration++ した結果 max を超える」場合のみ作動する backstop であり、
# 正常運用では record-review.sh 側が先に escalate を確定させる。両者は重複ではなく多層防御。
# iteration が上限を超えた状態でさらに produce/review/fix を続けようとする場合は
# escalate へ倒す（無限ループ・上限破りを防ぐ）。
if next_stage in ("produce", "review", "fix") and s["iteration"] > s["max_iterations"]:
    s["escalated"] = True
    s["stage"] = "escalate"
    s["updated_at"] = now
    s["history"].append({
        "iteration": s["iteration"],
        "stage": "escalate",
        "reason": "max_iterations 超過ガード（advance-state.sh）",
        "completed_at": now,
    })
    dump_atomic(s, p)
    print(f"phase={s['phase']} stage=escalate iteration={s['iteration']} (max={s['max_iterations']} 超過のため escalate)")
    sys.exit(0)

# 終端ステージ
if next_stage == "done":
    s["passed"] = True
elif next_stage == "escalate":
    s["escalated"] = True

s["stage"] = next_stage
s["updated_at"] = now

dump_atomic(s, p)

print(f"phase={s['phase']} stage={s['stage']} iteration={s['iteration']}")
PY
