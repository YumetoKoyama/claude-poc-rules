#!/usr/bin/env bash
# _common/scripts/check-id-uniqueness.sh
#
# 【R-01 対応】AC-XXX 採番の一意性検査（決定論）。
#   規約: AC は「機能スコープ採番」を正式採用（shared-canon §1 注記・RTM 主キーと同形式）。
#     (1) 同一 functional/*.md 内での AC 重複定義 → BLOCK
#     (2) functional/ 以外の要件文書で、複数機能に存在する AC 番号を
#         『機能名/AC-XXX』の修飾なしで参照 → BLOCK（参照先が曖昧）
#
# Usage:
#   check-id-uniqueness.sh <requirements-dir> [--gate]
#     --gate: BLOCK が 1 件でもあれば exit 1（ループ起動前ゲート用）
# 出力: findings JSON 配列を stdout（--merge-json で取り込み可能）
# Exit: 0=正常（--gate 時は BLOCK なし） / 1=--gate 時に BLOCK あり / 2=引数エラー
set -euo pipefail
REQ="${1:-}"; GATE=0
[ "${2:-}" = "--gate" ] && GATE=1
[ -z "$REQ" ] || [ ! -d "$REQ" ] && { echo "Usage: check-id-uniqueness.sh <requirements-dir> [--gate]" >&2; exit 2; }
REQ="$REQ" python3 <<'PY'
import json, os, re, sys, glob, collections

req = os.environ["REQ"].rstrip("/")
ac_re = re.compile(r"AC-\d{3}")
findings = []

# (1) functional/*.md 内の定義収集と同一ファイル内重複
defined = collections.defaultdict(set)   # AC -> {file}
for f in sorted(glob.glob(os.path.join(req, "functional", "*.md"))):
    per_line = collections.defaultdict(list)
    for i, ln in enumerate(open(f, encoding="utf-8"), 1):
        if not ln.lstrip().startswith("|"):
            continue
        cells = [c.strip() for c in ln.split("|")]
        for c in cells:
            if re.fullmatch(r"AC-\d{3}", c):   # セル単独 = 定義行
                per_line[c].append(i)
                defined[c].add(f)
    for ac, lns in per_line.items():
        if len(lns) > 1:
            findings.append({"severity": "BLOCK", "path": f, "line": lns[1],
                "category": "id-uniqueness",
                "message": f"{ac} が同一機能ファイル内で {len(lns)} 回定義されています（行 {lns}）。機能内で一意に採番してください",
                "suggested_fix": f"{ac} の重複行を再採番する"})

multi = {ac for ac, fs in defined.items() if len(fs) > 1}

# (2) functional 外の非修飾参照（複数機能に存在する AC のみ曖昧として BLOCK）
for f in sorted(glob.glob(os.path.join(req, "**", "*.md"), recursive=True)):
    rel = os.path.relpath(f, req)
    if rel.startswith("functional") or os.path.basename(f) == "オープン課題.md" or rel.startswith("_input"):
        continue
    for i, ln in enumerate(open(f, encoding="utf-8"), 1):
        for m in ac_re.finditer(ln):
            ac = m.group(0)
            if ac not in multi:
                continue
            pre = ln[max(0, m.start()-1):m.start()]
            if pre == "/":   # 『機能名/AC-XXX』の修飾済み
                continue
            findings.append({"severity": "BLOCK", "path": f, "line": i,
                "category": "id-uniqueness",
                "message": f"{ac} は複数の機能で採番されており（{len(defined[ac])} 機能）、修飾なしの参照は曖昧です。『機能名/{ac}』の形式で参照してください",
                "suggested_fix": f"『<機能名>/{ac}』に修飾する"})

print(json.dumps(findings, ensure_ascii=False, indent=2))
blocks = sum(1 for x in findings if x["severity"] == "BLOCK")
print(f"check-id-uniqueness: findings={len(findings)} (BLOCK={blocks})", file=sys.stderr)
sys.exit(0)
PY
rc=$?
[ $rc -ne 0 ] && exit $rc
if [ "$GATE" = "1" ]; then
  # 直前出力を再評価せず、再実行せずに済むよう一時再計算はしない: gate 用に findings を再取得
  n=$(REQ="$REQ" python3 - <<'PY'
import os, re, glob, collections
req = os.environ["REQ"].rstrip("/")
defined = collections.defaultdict(set); dup = 0
for f in sorted(glob.glob(os.path.join(req, "functional", "*.md"))):
    seen = collections.Counter()
    for ln in open(f, encoding="utf-8"):
        if not ln.lstrip().startswith("|"): continue
        for c in [c.strip() for c in ln.split("|")]:
            if re.fullmatch(r"AC-\d{3}", c):
                seen[c] += 1; defined[c].add(f)
    dup += sum(1 for v in seen.values() if v > 1)
multi = {a for a, fs in defined.items() if len(fs) > 1}
amb = 0
for f in sorted(glob.glob(os.path.join(req, "**", "*.md"), recursive=True)):
    rel = os.path.relpath(f, req)
    if rel.startswith(("functional", "_input")) or f.endswith("オープン課題.md"): continue
    for ln in open(f, encoding="utf-8"):
        for m in re.finditer(r"AC-\d{3}", ln):
            if m.group(0) in multi and ln[max(0, m.start()-1):m.start()] != "/": amb += 1
print(dup + amb)
PY
)
  if [ "$n" != "0" ]; then echo "NG: AC 一意性違反 $n 件（詳細は check-id-uniqueness.sh <dir> の findings 出力）" >&2; exit 1; fi
  echo "OK: AC 採番の一意性（機能内一意・修飾参照）に違反はありません" >&2
fi
