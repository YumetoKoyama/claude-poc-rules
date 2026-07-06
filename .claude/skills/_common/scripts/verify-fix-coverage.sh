#!/usr/bin/env bash
# _common/scripts/verify-fix-coverage.sh
#
# fix skill 実行後のゲート: 前回 review の BLOCK 指摘が対応されたかを検証する。
# 未対応 BLOCK があれば exit 1 で返し、オーケストレーターが fix を再実行する。
# review skill には結果を渡さない（判定の独立性を維持）。
#
# 検証方法:
#   1. fix 前のファイルハッシュ（snapshot JSON）と現在のファイルを比較
#   2. BLOCK の path が変更されていなければ「未対応」と判定
#   3. SUGGEST も検査するが、SUGGEST の未対応は警告のみ（exit 0）
#
# Usage:
#   # fix 実行前にスナップショットを取る:
#   verify-fix-coverage.sh snapshot <phase> <review-json-path>
#   → .skills-state/<phase>/pre-fix-snapshot.json を生成
#
#   # fix 実行後に検証する:
#   verify-fix-coverage.sh verify <phase> <review-json-path>
#   → exit 0: 全 BLOCK 対応済み
#   → exit 1: 未対応 BLOCK あり（stdout に未対応一覧の JSON）
#
set -euo pipefail

ACTION="${1:-}"
PHASE="${2:-}"
REVIEW_JSON="${3:-}"

if [[ -z "$ACTION" || -z "$PHASE" || -z "$REVIEW_JSON" ]]; then
  echo "Usage: verify-fix-coverage.sh <snapshot|verify> <phase> <review-json-path>" >&2
  exit 1
fi

# .skills-state の出力/参照先を phase から決定論的に解決（CWD 非依存・所有リポ集約）
# shellcheck source=_state-root.sh
source "$(dirname "${BASH_SOURCE[0]}")/_state-root.sh"
: "${STATE_ROOT:=$(resolve_state_root "$PHASE")}"
SNAPSHOT_FILE="${STATE_ROOT:-.}/.skills-state/${PHASE}/pre-fix-snapshot.json"

case "$ACTION" in
  snapshot)
    python3 - "$REVIEW_JSON" "$SNAPSHOT_FILE" << 'PY'
import json, hashlib, os, sys

review_path = sys.argv[1]
snapshot_path = sys.argv[2]

with open(review_path) as f:
    review = json.load(f)

# BLOCK と SUGGEST の参照ファイルのハッシュを記録
snapshot = {}
for finding in review.get("findings", []):
    sev = (finding.get("severity") or "").upper()
    if sev not in ("BLOCK", "SUGGEST"):
        continue
    path = finding.get("path", "")
    if not path or path in snapshot:
        continue
    if os.path.exists(path):
        with open(path, "rb") as f:
            snapshot[path] = hashlib.sha256(f.read()).hexdigest()
    else:
        snapshot[path] = "__NOT_FOUND__"

os.makedirs(os.path.dirname(snapshot_path), exist_ok=True)
with open(snapshot_path, "w") as f:
    json.dump(snapshot, f, ensure_ascii=False, indent=2)

print(f"snapshot: {len(snapshot)} files recorded")
PY
    ;;

  verify)
    python3 - "$REVIEW_JSON" "$SNAPSHOT_FILE" << 'PY'
import json, hashlib, os, sys

review_path = sys.argv[1]
snapshot_path = sys.argv[2]

if not os.path.exists(snapshot_path):
    print("ERROR: snapshot not found. Run 'snapshot' before fix.", file=sys.stderr)
    sys.exit(2)

with open(review_path) as f:
    review = json.load(f)
with open(snapshot_path) as f:
    snapshot = json.load(f)

# 各 BLOCK/SUGGEST の参照ファイルが変更されたかチェック
unaddressed_blocks = []
unaddressed_suggests = []

# finding ごとにチェック（同一ファイルに複数 finding がある場合もファイル単位で判定）
file_changed = {}
for path, old_hash in snapshot.items():
    if os.path.exists(path):
        with open(path, "rb") as f:
            new_hash = hashlib.sha256(f.read()).hexdigest()
        file_changed[path] = (new_hash != old_hash)
    else:
        # ファイルが消えた場合も「変更あり」（削除による対応の可能性）
        file_changed[path] = (old_hash != "__NOT_FOUND__")

for finding in review.get("findings", []):
    sev = (finding.get("severity") or "").upper()
    if sev not in ("BLOCK", "SUGGEST"):
        continue
    path = finding.get("path", "")
    if not path:
        continue
    changed = file_changed.get(path, True)  # snapshot に無いパスは対応済みとみなす
    if not changed:
        entry = {
            "severity": sev,
            "category": finding.get("category", ""),
            "path": path,
            "line": finding.get("line"),
            "message": finding.get("message", ""),
        }
        if sev == "BLOCK":
            unaddressed_blocks.append(entry)
        else:
            unaddressed_suggests.append(entry)

# 結果出力
result = {
    "unaddressed_blocks": len(unaddressed_blocks),
    "unaddressed_suggests": len(unaddressed_suggests),
    "blocks": unaddressed_blocks,
    "suggests": unaddressed_suggests,
}

print(json.dumps(result, ensure_ascii=False, indent=2))

if unaddressed_blocks:
    print(f"\nFAIL: {len(unaddressed_blocks)} BLOCK(s) unaddressed (file not modified by fix)", file=sys.stderr)
    sys.exit(1)
elif unaddressed_suggests:
    print(f"\nWARN: {len(unaddressed_suggests)} SUGGEST(s) unaddressed (file not modified by fix)", file=sys.stderr)
    sys.exit(0)
else:
    print("\nOK: all BLOCKs addressed", file=sys.stderr)
    sys.exit(0)
PY
    ;;

  *)
    echo "Unknown action: $ACTION (use 'snapshot' or 'verify')" >&2
    exit 1
    ;;
esac
