#!/usr/bin/env bash
# _common/scripts/record-review.sh
#
# 第1層: review skill が生成した review JSON を state に取り込む。
# BLOCK 件数 + SUGGEST 件数（全カテゴリ）を見て passed=true / stage=fix / escalate を判定する（決定論）。
#
# ※ エスカレーション判定は本スクリプトに一元化している。advance-state.sh は
#   stage 遷移と iteration++、および max_iterations 超過ガードのみを担当する。
#
# 終了条件（全 *-loop 工程で共通＝requirements / design / implement / integration）:
#   - PASS:     BLOCK == 0 かつ SUGGEST == 0（全カテゴリ）
#   - fix:      上記を満たさず、iteration < max_iterations
#   - escalate: 上記を満たさず、iteration >= max_iterations
#               （BLOCK が残る場合だけでなく、SUGGEST が残ったまま上限到達した場合も escalate＝素通りさせない。RC-08）
#
# 重要カテゴリ（CLAUDE.md「改善ループの終了条件」と同一定義。フェーズ別の別名も網羅）:
#   界面契約: contract / contract-consistency / type_three_way / error-response
#   認可・セキュリティ: security / security-baseline / security-design / authorization / authz / authz-screen
#   並行性: concurrency
#   データ連鎖: data-sufficiency / data_sufficiency / dead-field / data-chain
#   BE↔DB整合: db-schema-completeness / db-contract
#
# 閾値は環境変数 SUGGEST_THRESHOLD で変更可能（既定 0 = SUGGEST が1件でもあれば素通りさせない）。
#
# === 設計側カテゴリの即エスカレート（integration 工程の設計差し戻し）===
# ESCALATE_CATEGORIES（カンマ区切り・既定 "integration_design"）に含まれる category の
# BLOCK が 1 件でもあれば、iteration に関わらず即 escalate する。
# 設計側の不整合は fix 反復では解消できない（設計書は本工程で書き換えない）ため、
# integration-test-loop の「設計側 BLOCK は ESCALATE」をここ（決定論層）で担保する。
#
# === BLOCK 由来分類（「fix が生んだ BLOCK か / 潜在 BLOCK の表面化か」を区別する）===
# レビューで毎回違う BLOCK が出る場合、それが (a) 既存の潜在 BLOCK の表面化なのか、
# (b) 直前の fix が新しく生んだリグレッションなのかを機械的に切り分ける。
# 各 review 実行時に、対象ツリー（state.artifact_path 配下の git 追跡＋未追跡非 ignore ファイル）の
# sha256 スナップショットと、BLOCK の安定フィンガープリント（category|path|message-slug）を
# サイドカーに保存する。次の review では:
#   - carried_over  : 前 review にも同一フィンガープリントの BLOCK が存在（= fix が解消できていない）
#   - regressed     : 今回新規の BLOCK で、その path が「前回 review 以降（=直前の fix）に変更されたファイル」に含まれる（= fix 起因の可能性大）
#   - newly_surfaced: 今回新規の BLOCK で、fix が触っていないファイル（= 潜在 BLOCK の表面化）
#   - initial       : 初回 review（比較対象なし）
# 分類は history と state.block_classification に記録する（判定そのものは変えない＝可視化が目的）。
# サイドカー:
#   .skills-state/<phase>/tree-snapshot.json   … 前回 review 時点のツリーハッシュ
#   .skills-state/<phase>/prev-blocks.json     … 前回 review の BLOCK フィンガープリント一覧
# 任意ノブ: REGRESSION_ESCALATE=1 を設定すると、clean でない review で regressed>0 のとき
#           iteration に関わらず即 escalate する（fix がリグレッションを生む状態を素通しさせない）。既定は off。
#
# Usage:
#   record-review.sh <phase> <review_json_path>

set -euo pipefail

PHASE="${1:-}"
REVIEW_JSON="${2:-}"
: "${SUGGEST_THRESHOLD:=0}"
: "${REGRESSION_ESCALATE:=0}"
: "${ESCALATE_CATEGORIES:=integration_design}"

# .skills-state の出力/参照先を phase から決定論的に解決（CWD 非依存・所有リポ集約）
# shellcheck source=_state-root.sh
source "$(dirname "${BASH_SOURCE[0]}")/_state-root.sh"
: "${STATE_ROOT:=$(resolve_state_root "$PHASE")}"
STATE_FILE="${STATE_ROOT:-.}/.skills-state/${PHASE}/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: state file not found: $STATE_FILE" >&2
  exit 1
fi
if [[ ! -f "$REVIEW_JSON" ]]; then
  echo "ERROR: review JSON not found: $REVIEW_JSON" >&2
  exit 1
fi

STATE_DIR="$(dirname "$STATE_FILE")"

SUGGEST_THRESHOLD="$SUGGEST_THRESHOLD" REGRESSION_ESCALATE="$REGRESSION_ESCALATE" \
ESCALATE_CATEGORIES="$ESCALATE_CATEGORIES" \
STATE_DIR="$STATE_DIR" python3 - "$STATE_FILE" "$REVIEW_JSON" <<'PY'
import json, datetime, os, sys, re, hashlib, subprocess, tempfile

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

sp = sys.argv[1]
rp_in = sys.argv[2]
threshold = int(os.environ.get("SUGGEST_THRESHOLD", "0"))
regression_escalate = os.environ.get("REGRESSION_ESCALATE", "0").strip().lower() in ("1", "true", "yes")
state_dir = os.environ.get("STATE_DIR", ".")
SNAPSHOT_FILE = os.path.join(state_dir, "tree-snapshot.json")
PREVBLOCKS_FILE = os.path.join(state_dir, "prev-blocks.json")

# 重要カテゴリ（CLAUDE.md と一致。フェーズ別別名を網羅）
IMPORTANT = {
  "contract", "contract-consistency", "type_three_way", "error-response",
  "security", "security-baseline", "security-design", "authorization", "authz", "authz-screen",
  "concurrency",
  "data-sufficiency", "data_sufficiency", "dead-field", "data-chain",
  "db-schema-completeness", "db-contract",
}

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

counts = {"block": 0, "suggest": 0, "nit": 0, "important_suggest": 0}
for x in r.get("findings", []):
  sev = (x.get("severity") or "").upper()
  cat = (x.get("category") or "").strip()
  if sev == "BLOCK":
    counts["block"] += 1
  elif sev == "SUGGEST":
    counts["suggest"] += 1
    if cat in IMPORTANT:
      counts["important_suggest"] += 1
  elif sev == "NIT":
    counts["nit"] += 1

# ---- BLOCK 由来分類（regressed / newly_surfaced / carried_over / initial）----
def _slug(msg):
  m = (msg or "").lower()
  m = re.sub(r"\s+", " ", m).strip()
  # 行番号・桁などの揺れに強くするため記号類を落とし、英数＋日本語のみ残す
  m = re.sub(r"[^0-9a-zぁ-んァ-ヶ一-龠ー ]", "", m)
  return m[:80]

def _fp(x):
  cat = (x.get("category") or "").strip()
  path = (x.get("path") or "").strip()
  return f"{cat}|{path}|{_slug(x.get('message'))}"

def _tracked_files(pathspec):
  """git 追跡＋未追跡非 ignore ファイルの一覧（pathspec で絞り込み）。git 不可なら None。"""
  try:
    out = subprocess.run(
      ["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", pathspec],
      capture_output=True, text=True, cwd=os.getcwd())
    if out.returncode != 0:
      return None
    return sorted({ln for ln in out.stdout.splitlines() if ln.strip()})
  except Exception:
    return None

def _snapshot(pathspec):
  files = _tracked_files(pathspec)
  if files is None:
    return None
  snap = {}
  for p in files:
    try:
      with open(p, "rb") as fh:
        snap[p] = hashlib.sha256(fh.read()).hexdigest()
    except Exception:
      snap[p] = "__ERR__"
  return snap

# 対象ツリーは state.artifact_path 配下に絞る（"." は全リポジトリ）
pathspec = (s.get("artifact_path") or ".").strip() or "."
cur_snapshot = _snapshot(pathspec)

# 前回スナップショット・前回 BLOCK フィンガープリントの読み込み
prev_snapshot = None
if os.path.exists(SNAPSHOT_FILE):
  try:
    with open(SNAPSHOT_FILE) as fh:
      prev_snapshot = json.load(fh)
  except Exception:
    prev_snapshot = None

prev_blocks_exists = os.path.exists(PREVBLOCKS_FILE)
prev_block_fps = set()
if prev_blocks_exists:
  try:
    with open(PREVBLOCKS_FILE) as fh:
      prev_block_fps = set(json.load(fh))
  except Exception:
    prev_block_fps = set()

# 前回 review 以降（=直前の fix）に変更されたファイル集合
changed_since_last = None
if cur_snapshot is not None and prev_snapshot is not None:
  changed_since_last = set()
  for p, h in cur_snapshot.items():
    if prev_snapshot.get(p) != h:
      changed_since_last.add(p)
  for p in prev_snapshot:            # 削除されたファイルも「変更」とみなす
    if p not in cur_snapshot:
      changed_since_last.add(p)

# 初回判定: prev-blocks サイドカーが無ければ比較対象なし＝initial
first_review = not prev_blocks_exists

classification = {"carried_over": 0, "regressed": 0, "newly_surfaced": 0, "initial": 0, "unknown": 0}
classified = []
cur_block_fps = []
for x in r.get("findings", []):
  if (x.get("severity") or "").upper() != "BLOCK":
    continue
  fp = _fp(x)
  cur_block_fps.append(fp)
  path = (x.get("path") or "").strip()
  if first_review:
    cls = "initial"
  elif fp in prev_block_fps:
    cls = "carried_over"
  elif changed_since_last is None:
    cls = "unknown"                  # git 不可でファイル変更を判定できない
  elif path in changed_since_last:
    cls = "regressed"
  else:
    cls = "newly_surfaced"
  classification[cls] += 1
  classified.append({"category": (x.get("category") or "").strip(), "path": path, "class": cls})

# 設計側カテゴリの BLOCK（fix 反復では解消不能 → 即 escalate 対象）
esc_cats = {c.strip() for c in os.environ.get("ESCALATE_CATEGORIES", "integration_design").split(",") if c.strip()}
design_blocks = [
  x for x in r.get("findings", [])
  if (x.get("severity") or "").upper() == "BLOCK" and (x.get("category") or "").strip() in esc_cats
]

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
s["last_review_path"] = rp
s["review_counts"] = counts
s["block_classification"] = classification
s["updated_at"] = now

# review 完了イベントを history に必ず記録する（件数＋分類つき）
s.setdefault("history", []).append({
  "iteration": s["iteration"],
  "stage": "review",
  "block": counts["block"],
  "suggest": counts["suggest"],
  "important_suggest": counts["important_suggest"],
  "nit": counts["nit"],
  "block_classification": classification,
  "completed_at": now,
})

# 終了条件（全工程共通。エスカレーション判定はここに一元化）
clean = (counts["block"] == 0) and (counts["suggest"] <= threshold)
if clean:
  s["passed"] = True
  s["stage"] = "done"
  s["history"].append({"iteration": s["iteration"], "stage": "done", "completed_at": now})
else:
  # 任意ノブ: fix がリグレッションを生んでいる場合、上限未満でも即 escalate する
  force_escalate = regression_escalate and classification["regressed"] > 0
  # 設計側カテゴリ BLOCK は iteration に関わらず即 escalate（設計フェーズへ差し戻し）
  design_escalate = len(design_blocks) > 0
  if s["iteration"] >= s["max_iterations"] or force_escalate or design_escalate:
    s["escalated"] = True
    s["stage"] = "escalate"
    reason = []
    if counts["block"] > 0:
      reason.append(f"BLOCK {counts['block']}")
    if counts["suggest"] > threshold:
      reason.append(f"SUGGEST {counts['suggest']}(>{threshold})")
    if force_escalate:
      reason.append(f"REGRESSED {classification['regressed']}(fix起因)")
    if design_escalate:
      cats = sorted({(x.get("category") or "").strip() for x in design_blocks})
      reason.append(f"DESIGN-SIDE BLOCK {len(design_blocks)}件({','.join(cats)}: 設計フェーズへ差し戻し)")
    s["history"].append({"iteration": s["iteration"], "stage": "escalate",
                         "reason": " / ".join(reason), "completed_at": now})
  else:
    s["stage"] = "fix"

dump_atomic(s, sp)

# 次の review 用にサイドカーを更新（state は本スクリプトのみが書く＝サイドカーも同様）
if cur_snapshot is not None:
  dump_atomic(cur_snapshot, SNAPSHOT_FILE)
dump_atomic(sorted(set(cur_block_fps)), PREVBLOCKS_FILE)

# fix がリグレッションを生んだ可能性を stderr に明示（オーケストレーター/人手が気づけるように）
if classification["regressed"] > 0:
  print(f"WARN: 直前の fix が新規 BLOCK を生んだ可能性 (regressed={classification['regressed']})。"
        f"潜在 BLOCK の表面化(newly_surfaced={classification['newly_surfaced']})とは区別されています。", file=sys.stderr)
if changed_since_last is None and not first_review:
  print("WARN: git でファイル変更を判定できないため regressed/newly_surfaced を unknown 扱いにしました。", file=sys.stderr)

print(f"block={counts['block']} suggest={counts['suggest']}(threshold={threshold}) "
      f"nit={counts['nit']} "
      f"regressed={classification['regressed']} newly={classification['newly_surfaced']} "
      f"carried={classification['carried_over']} next_stage={s['stage']}")
PY
