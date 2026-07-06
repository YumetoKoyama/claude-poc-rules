#!/usr/bin/env bash
# _common/scripts/check-confirmed-values.sh
#
# 第1層（決定論）: closed 済みオープン課題（Q-NF* / Q-DM* / Q-J* / Q-A* / Q-EI* / Q-MIG* 等）の
# 「確定値」と、その課題 ID を引用している設計・要件記述の数値が矛盾していないかを機械検証する。
#
# 背景: 「Q-NF3 = 通知保持 3 日」のように要件採択者が closed で確定した値が、
#       設計側で別の値（例: 30 日）で書かれていても、状態だけ見る check-open-issues.sh は
#       検出できない。本スクリプトは確定「値」の横串一致を決定論で担保する（review の揺れを排除）。
#
# 検査:
#   1) docs/requirements/オープン課題.md の各行から「課題 ID」「状態」「確定値セル」を抽出する。
#   2) 確定値セルから (数値, 単位) ペアを抽出する（単位: 日/分/時間/週/月/年/回/世代/文字/桁/円/% 等。
#      日↔days・分↔minutes・時間↔hours の英日同義を正規化）。
#   3) 指定ディレクトリ配下の .md / .yaml を走査し、ある課題 ID（例: 「Q-NF3」）を含む行に出現する
#      (数値, 単位) を抽出。確定値と「同じ単位なのに異なる値」なら不一致として findings に出す。
#        - その単位の確定値が 1 個だけ（例: 日={3}）→ BLOCK（明確な矛盾）
#        - その単位の確定値が複数（例: 分={30,60}）→ SUGGEST（取り違えの疑い・誤検知抑制）
#      ただし以下のケースは誤検知抑制のため降格またはスキップする:
#        - (B) 差が ±1 かつ行に境界値・バリデーション系キーワードがある → SUGGEST に降格
#        - (C) 行に「違反」「異常系」等のキーワードがある → スキップ（意図的な逸脱記述）
#
# Usage:
#   check-confirmed-values.sh <requirements_dir> <scan_dir> [<scan_dir> ...]
#     <requirements_dir> : オープン課題.md を含む要件ディレクトリ（例: docs/requirements）
#     <scan_dir>         : 引用整合を検査する対象（例: docs/design docs/requirements）
#
# 出力: findings JSON 配列を stdout（severity/path/line/category/message/suggested_fix）。
# Exit: 0=正常（findings 有無に関わらず） / 2=引数・実行環境エラー
#       ※ オープン課題.md が見つからない場合は空配列 [] を出して 0（前倒し運用で未整備でも止めない）

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "ERROR: 引数が不足しています" >&2
  echo "Usage: check-confirmed-values.sh <requirements_dir> <scan_dir> [<scan_dir> ...]" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません" >&2
  exit 2
fi

python3 - "$@" <<'PY'
import json, os, re, sys

req_dir = sys.argv[1]
scan_dirs = sys.argv[2:]

# --- 単位の同義語（正規化）。長い綴りを先に並べて貪欲一致させる ---
UNIT_SYNONYMS = [
    ("day",   ["日間", "日", "days", "day"]),
    ("min",   ["分間", "分", "minutes", "minute", "min"]),
    ("hour",  ["時間", "hours", "hour"]),
    ("week",  ["週間", "週", "weeks", "week"]),
    ("month", ["ヶ月", "カ月", "か月", "months", "month"]),
    ("year",  ["年間", "年", "years", "year"]),
    ("count", ["回"]),
    ("gen",   ["世代"]),
    ("char",  ["文字", "characters", "chars"]),
    ("digit", ["桁", "digits"]),
    ("jpy",   ["円"]),
    ("pct",   ["%", "％"]),
]
# 同義語→正規単位、および正規表現用の選択肢（長さ降順）
SYN_TO_CANON = {}
ALL_SYNS = []
for canon, syns in UNIT_SYNONYMS:
    for s in syns:
        SYN_TO_CANON[s] = canon
        ALL_SYNS.append(s)
ALL_SYNS.sort(key=len, reverse=True)
UNIT_ALT = "|".join(re.escape(s) for s in ALL_SYNS)
# (A) カンマ区切り数値に対応: [\d,]+ で「9,999,999,999」等を丸ごと捕捉する
PAIR_RE = re.compile(r"([\d,]+)\s*(" + UNIT_ALT + r")")
QID_RE = re.compile(r"Q-[A-Z]{1,4}\d+")

# (B) 境界値・バリデーション条件を示すキーワード（差 ±1 の降格判定用）
BOUNDARY_KW_RE = re.compile(r"以上|以下|超[えのが]|未満|境界値|バリデーション|エラー条件|エラーメッセージ|エラー表示")
# (C) 違反・異常系シナリオを示すキーワード（スキップ判定用）
VIOLATION_KW_RE = re.compile(r"違反|異常系|エラーケース|NG\b|不正[なに値]|拒否")

def extract_pairs(text):
    """text 中の (値:int, 正規単位:str) の集合を返す"""
    out = set()
    for m in PAIR_RE.finditer(text):
        # (A) カンマを除去してから int 変換
        raw = m.group(1).replace(",", "")
        if not raw:
            continue
        val = int(raw)
        unit = SYN_TO_CANON.get(m.group(2))
        if unit:
            out.add((val, unit))
    return out

# --- 1) オープン課題.md を探す ---
open_issue_path = None
for root, dirs, files in os.walk(req_dir):
    dirs[:] = [d for d in dirs if not d.startswith(".") and d != "node_modules"]
    for f in files:
        if f == "オープン課題.md":
            open_issue_path = os.path.join(root, f)
            break
    if open_issue_path:
        break

findings = []
if not open_issue_path:
    print(json.dumps(findings, ensure_ascii=False))
    sys.exit(0)

# --- 2) closed 行から Q-ID → {unit: set(values)} を構築 ---
# confirmed[qid][unit] = set(values)
confirmed = {}
with open(open_issue_path, encoding="utf-8") as fp:
    for raw in fp:
        line = raw.rstrip("\n")
        if not line.lstrip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        # Q-ID セルを探す
        qids = [c for c in cells if re.fullmatch(r"Q-[A-Z]{1,4}\d+", c)]
        if not qids:
            continue
        qid = qids[0]
        # 状態セル（closed/open）と、その直後の確定値セル
        state_idx = None
        for i, c in enumerate(cells):
            if c.lower() in ("closed", "open"):
                state_idx = i
                break
        if state_idx is None or cells[state_idx].lower() != "closed":
            continue
        confirm_cell = cells[state_idx + 1] if state_idx + 1 < len(cells) else ""
        pairs = extract_pairs(confirm_cell)
        if not pairs:
            continue
        d = confirmed.setdefault(qid, {})
        for val, unit in pairs:
            d.setdefault(unit, set()).add(val)

if not confirmed:
    print(json.dumps(findings, ensure_ascii=False))
    sys.exit(0)

# --- 3) scan_dirs を走査し、Q-ID を含む行の数値矛盾を検出 ---
SKIP_DIRS = {".git", "node_modules", ".skills-state", "target", "build", "dist", "__pycache__"}
# 派生・報告文書はバグを「引用」しているため対象外（オープン課題.md 自身も別途除外）
SKIP_FILES = {"オープン課題.md", "レビュー結果.md", "変更履歴.md"}
SCAN_EXTS = {".md", ".yaml", ".yml"}
seen = set()

def scan_file(path):
    if os.path.basename(path) in SKIP_FILES:
        return
    try:
        with open(path, encoding="utf-8") as fp:
            lines = fp.readlines()
    except (OSError, UnicodeDecodeError):
        return
    for lineno, raw in enumerate(lines, 1):
        line = raw.rstrip("\n")
        qids_here = set(QID_RE.findall(line))
        if not qids_here:
            continue
        qids_here &= set(confirmed.keys())
        if len(qids_here) != 1:
            continue  # 0件=対象外 / 2件以上=どの数値がどのQ-IDの値か機械的に確定できない（誤検知防止）
        # オープン課題.md 自身の定義行（確定値セルそのもの）は除外
        if os.path.abspath(path) == os.path.abspath(open_issue_path):
            continue
        # (C) 違反・異常系シナリオの記述行はスキップ（意図的に確定値と異なる値を書いている）
        if VIOLATION_KW_RE.search(line):
            continue
        line_pairs = extract_pairs(line)
        if not line_pairs:
            continue
        for qid in qids_here:
            unit_map = confirmed[qid]
            for val, unit in line_pairs:
                if unit not in unit_map:
                    continue  # 確定値に無い単位は対象外（無関係な数値の誤検知防止）
                allowed = unit_map[unit]
                if val in allowed:
                    continue  # 一致
                # (B) 差が ±1 かつ境界値キーワードがある場合は SUGGEST に降格
                diff_one = any(abs(val - a) == 1 for a in allowed)
                if diff_one and BOUNDARY_KW_RE.search(line):
                    sev = "SUGGEST"
                else:
                    sev = "BLOCK" if len(allowed) == 1 else "SUGGEST"
                allowed_str = "・".join(str(v) for v in sorted(allowed))
                key = (path, lineno, qid, val, unit)
                if key in seen:
                    continue
                seen.add(key)
                # (B) 降格時はメッセージに理由を付記
                boundary_note = ""
                if diff_one and BOUNDARY_KW_RE.search(line):
                    boundary_note = "（境界値条件の可能性あり。確定値との差が ±1 のため SUGGEST に降格）"
                findings.append({
                    "severity": sev,
                    "path": path,
                    "line": lineno,
                    "category": "confirmed-value",
                    "message": (
                        f"「{qid}」の確定値（{unit}={allowed_str}）と設計記述の値（{val}）が矛盾しています。{boundary_note}"
                        f"該当行: ...{line.strip()[:80]}"
                    ),
                    "suggested_fix": (
                        f"オープン課題.md の {qid} 確定値（{unit}={allowed_str}）に合わせて記述を修正する。"
                        f"確定値側を変える場合は要件採択者の再採択が必要。"
                    ),
                })

for sd in scan_dirs:
    if os.path.isfile(sd):
        if os.path.splitext(sd)[1].lower() in SCAN_EXTS and sd not in seen:
            scan_file(sd)
        continue
    for root, dirs, files in os.walk(sd):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        for f in files:
            if os.path.splitext(f)[1].lower() in SCAN_EXTS:
                scan_file(os.path.join(root, f))

# BLOCK→SUGGEST 順
order = {"BLOCK": 0, "SUGGEST": 1, "NIT": 2}
findings.sort(key=lambda x: (order.get(x["severity"], 9), x["path"], x["line"] or 0))
print(json.dumps(findings, ensure_ascii=False, indent=2))
PY
