#!/usr/bin/env bash
# _common/scripts/approve-phase.sh
#
# 第1層（決定論）: あるフェーズの成果物を「人手レビューで採択した」ことを
# 機械可読なマーカー（.skills-state/<phase>/approved.json）として記録する。
#
# 目的: 「採択前は次工程に進まない」という CLAUDE.md のゲートを、AI の自己申告ではなく
#       マーカーファイルの存在で機械的に強制できるようにする。後続 skill
#       （design-from-requirements / create-issues-from-design / implement-from-issue 等）は
#       前段フェーズの approved.json の存在を前提条件として確認する。
#
# Usage:
#   approve-phase.sh <phase> [approver] [note]
#     <phase>    : requirements | design
#     [approver] : 採択者名（省略時 "unknown"）
#     [note]     : 備考（省略可）
#
#   採択を取り消す（やり直す）場合は --revoke を第2引数に渡す:
#     approve-phase.sh <phase> --revoke
#
# 出力: 書き出した approved.json のパスを stdout に 1 行

set -euo pipefail

PHASE="${1:-}"
ARG2="${2:-}"
NOTE="${3:-}"

if [[ -z "$PHASE" ]]; then
  echo "ERROR: phase が指定されていません（requirements | design）" >&2
  exit 2
fi
case "$PHASE" in
  requirements|design) ;;
  *) echo "ERROR: 採択対象は requirements / design のみです: $PHASE" >&2; exit 2 ;;
esac

STATE_DIR=".skills-state/${PHASE}"
APPROVED_FILE="${STATE_DIR}/approved.json"
mkdir -p "$STATE_DIR"

if [[ "$ARG2" == "--revoke" ]]; then
  if [[ -f "$APPROVED_FILE" ]]; then
    : > /dev/null
    python3 - "$APPROVED_FILE" <<'PY'
import json, sys, datetime
p = sys.argv[1]
with open(p) as f:
    d = json.load(f)
d["approved"] = False
d["revoked_at"] = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
with open(p, "w") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
PY
    echo "$APPROVED_FILE"
    echo "revoked: $PHASE" >&2
  else
    echo "WARN: 採択マーカーが存在しません（既に未採択）: $APPROVED_FILE" >&2
  fi
  exit 0
fi

APPROVER="${ARG2:-unknown}"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'no-git')"

python3 - "$APPROVED_FILE" "$PHASE" "$APPROVER" "$NOTE" "$NOW" "$GIT_SHA" <<'PY'
import json, sys
p, phase, approver, note, now, sha = sys.argv[1:7]
data = {
  "phase": phase,
  "approved": True,
  "approver": approver,
  "note": note,
  "approved_at": now,
  "git_sha": sha,
}
with open(p, "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PY

echo "$APPROVED_FILE"
echo "approved: phase=$PHASE approver=$APPROVER sha=$GIT_SHA" >&2
