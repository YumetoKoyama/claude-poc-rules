#!/usr/bin/env bash
# _common/scripts/check-closed-reflected.sh
#
# 【R-02 対応】クローズ済みオープン課題の確定値が本文へ反映されているかの検査（決定論）。
#   症状: Q をクローズしても要件本文に「未確定/要確定/要確認 → Q-XXX」のプレース
#   ホルダが残り、下流（設計 fix）が採択済み要件を書き換える誘因になる（D-01 の根本原因）。
#   検査: オープン課題.md で closed の Q-ID を、未確定系キーワードと同一行で参照して
#   いる行を BLOCK として報告する。
#
# Usage:
#   check-closed-reflected.sh <requirements-dir> [<scan-dir> ...] [--gate]
#     scan-dir 省略時: requirements-dir 自身を走査
#     --gate : BLOCK が 1 件でもあれば exit 1（採択チェック・design-loop 起動前ゲート用）
# 出力: findings JSON 配列を stdout（--merge-json で取り込み可能）
set -euo pipefail
GATE=0; ARGS=()
for a in "$@"; do [ "$a" = "--gate" ] && GATE=1 || ARGS+=("$a"); done
REQ="${ARGS[0]:-}"
[ -z "$REQ" ] || [ ! -d "$REQ" ] && { echo "Usage: check-closed-reflected.sh <requirements-dir> [<scan-dir>...] [--gate]" >&2; exit 2; }
SCANS="${ARGS[@]:1}"; [ -z "$SCANS" ] && SCANS="$REQ"
out=$(REQ="$REQ" SCANS="$SCANS" python3 <<'PY'
import json, os, re, sys, glob

req = os.environ["REQ"].rstrip("/")
scans = os.environ["SCANS"].split()
oq = os.path.join(req, "オープン課題.md")
findings = []
closed = set()
OPEN_T = {"open", "未解決", "未確定", "未対応", "対応中", "保留", "検討中"}
CLOSED_T = {"closed", "クローズ", "クローズ済", "解決済", "対応済", "完了", "確定済", "済", "済み"}
if os.path.isfile(oq):
    for ln in open(oq, encoding="utf-8"):
        if not ln.lstrip().startswith("|"):
            continue
        cells = [c.strip() for c in ln.split("|")]
        qids = [c for c in cells if re.fullmatch(r"Q-[A-Z]+\d+", c)]
        state = None
        for c in cells:
            lc = c.lower()
            if lc in OPEN_T: state = "open"; break
            if lc in CLOSED_T: state = state or "closed"
        if state == "closed":
            closed.update(qids)

kw = re.compile(r"未確定|要確定|要確認")
qref = re.compile(r"Q-[A-Z]+\d+")
for sd in scans:
    for f in sorted(glob.glob(os.path.join(sd, "**", "*.md"), recursive=True)):
        if os.path.basename(f) in ("オープン課題.md", "レビュー結果.md") or "/_input/" in f.replace(os.sep, "/"):
            continue
        for i, ln in enumerate(open(f, encoding="utf-8"), 1):
            if not kw.search(ln):
                continue
            hit = sorted(set(qref.findall(ln)) & closed)
            if hit:
                findings.append({"severity": "BLOCK", "path": f, "line": i,
                    "category": "closed-not-reflected",
                    "message": f"クローズ済み課題 {'/'.join(hit)} の確定値が本文に未反映です（未確定系プレースホルダが残存）。オープン課題.md の決定内容を本文へ反映してください",
                    "suggested_fix": "オープン課題.md の該当行の決定内容で本文を更新し、プレースホルダを『確定』表記に置換する"})
print(json.dumps(findings, ensure_ascii=False, indent=2))
print(f"check-closed-reflected: findings={len(findings)}", file=sys.stderr)
PY
)
echo "$out"
if [ "$GATE" = "1" ]; then
  n=$(printf '%s' "$out" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
  if [ "$n" != "0" ]; then echo "NG: クローズ済み課題の本文未反映 $n 件。採択前に反映してください（R-02）" >&2; exit 1; fi
  echo "OK: クローズ済み課題の確定値はすべて本文へ反映済みです" >&2
fi
