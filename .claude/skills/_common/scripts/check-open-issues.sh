#!/usr/bin/env bash
# _common/scripts/check-open-issues.sh
#
# 用途（RC-10）:
#   docs/requirements/オープン課題.md の設計着手前クローズ必須課題が open のまま
#   残っていないかを検査する。1 件でも open なら設計着手前ゲートで exit 1。
#
#   必須課題の決定（R-03 対応・文書を正とする）:
#     1. オープン課題.md の「設計着手前にクローズ必須の課題区分」節に列挙された
#        バッククォート付き Q-ID（例: `Q-NF1`）を必須集合とする。
#     2. 当該節が無い場合のみ、従来の接頭辞一律（Q-NF*/Q-DM*/Q-EI*/Q-MIG*）に
#        フォールバックする。
#
#   open/closed の判定（R-04 対応・部分文字列汚染の排除）:
#     - テーブル行: セル値が状態語に「完全一致」する場合のみ採用（"open" を含む
#       だけの説明文・スクリプト名では判定しない）。
#     - 非テーブル行: `[状態: xxx]` 記法のみ判定に使う。
#     - 状態が読めない必須課題は安全側で open 扱い（NG）。
#
# Usage:
#   check-open-issues.sh [<requirements-dir>]
# Exit: 0=必須課題すべて closed / 1=open 残存 / 2=対象不在等

set -euo pipefail

REQ_DIR="${1:-}"
if [[ -z "$REQ_DIR" ]]; then
  for c in "./docs/requirements" "./claude-poc-docs/docs/requirements"; do
    [[ -d "$c" ]] && REQ_DIR="$c" && break
  done
fi
[[ -z "$REQ_DIR" ]] && REQ_DIR="./docs/requirements"

OQ="$REQ_DIR/オープン課題.md"
if [[ ! -f "$OQ" ]]; then
  echo "INFO: オープン課題.md がありません: $OQ（検査をスキップ）"
  exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません" >&2; exit 2
fi

python3 - "$OQ" <<'PY'
import sys, re

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    lines = f.readlines()

PREFIXES = ("Q-NF", "Q-DM", "Q-EI", "Q-MIG")
id_re = re.compile(r"\b(Q-[A-Z]+\d+)\b")
OPEN_T = {"open", "未解決", "未確定", "未対応", "未済", "対応中", "保留", "調査中", "検討中", "要確定", "要対応", "起票"}
CLOSED_T = {"closed", "クローズ済", "クローズ", "解決済", "対応済", "完了", "確定済", "済", "済み"}

# 1) 必須集合: 「設計着手前にクローズ必須の課題区分」節のバッククォート Q-ID
must = set()
in_sec = False
for ln in lines:
    if re.match(r"#{2,4}\s*設計着手前にクローズ必須", ln):
        in_sec = True
        continue
    if in_sec and re.match(r"#{2,4}\s", ln):
        break
    if in_sec:
        must.update(re.findall(r"`(Q-[A-Z]+\d+)`", ln))

fallback = not must

# 2) 状態判定: テーブル行のセル完全一致 or [状態: xxx] 記法のみ
def cell_state(c):
    v = c.strip().lower()
    if v in OPEN_T: return "open"
    if v in CLOSED_T: return "closed"
    return None

seen = {}       # qid -> state（open 優先）
table_ids = set()
st_re = re.compile(r"\[状態[:：]\s*([^\]\s]+)\]")
for ln in lines:
    qids = set(id_re.findall(ln))
    if not qids:
        continue
    if ln.lstrip().startswith("|"):
        table_ids.update(qids)
        states = [cell_state(c) for c in ln.split("|")]
        row = "open" if "open" in states else ("closed" if "closed" in states else None)
    else:
        m = st_re.search(ln)
        row = cell_state(m.group(1)) if m else None
    if row is None:
        continue
    for q in qids:
        if seen.get(q) != "open":     # open は粘着（安全側）
            seen[q] = row if seen.get(q) is None or row == "open" else seen[q]
        if row == "open":
            seen[q] = "open"

required = must if must else {q for q in table_ids if q.startswith(PREFIXES)}

ng = 0
for q in sorted(required):
    st = seen.get(q)
    if st is None:
        print(f"NG: 必須クローズ課題 {q} の状態（open/closed）が読み取れません（安全側で open 扱い）。課題一覧表の状態セルに明記してください")
        ng = 1
    elif st == "open":
        print(f"NG: 設計着手前クローズ必須課題 {q} が open のままです")
        ng = 1

if not required:
    print("INFO: 設計着手前クローズ必須課題は存在しません")

src = "文書の必須区分表" if not fallback else "接頭辞既定（Q-NF*/Q-DM*/Q-EI*/Q-MIG*）"
if ng:
    print("")
    print(f"設計フェーズ（design-from-requirements 以降）には進めません（RC-10・必須集合の根拠: {src}）。")
    print("必須課題を要件採択者がクローズしてから設計に着手してください。")
    sys.exit(1)

print(f"OK: 設計着手前クローズ必須課題はすべて closed です（RC-10・必須集合の根拠: {src}・{len(required)} 件）。")
PY
