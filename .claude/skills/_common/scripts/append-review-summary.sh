#!/usr/bin/env bash
# _common/scripts/append-review-summary.sh
#
# オーケストレーター（*-loop）が record-review.sh の後に呼ぶ。
# review JSON を人間可読 Markdown に変換し、レビュー結果.md の最上部に追記する。
# review skill 自身はこのファイルを読み書きしない（判定の独立性を保つため）。
#
# Usage:
#   append-review-summary.sh <phase> <review-json-path> [--issue <ISSUE_NUMBER>]
#
# phase:
#   requirements → docs/requirements/レビュー結果.md
#   design       → docs/design/レビュー結果.md
#   implement    → docs/test/レビュー結果/implement-issue-<ISSUE>.md（--issue 必須）
#
# パス解決: カレント直下に claude-poc-docs/ があれば docs 系パスに前置する。
#           implement の場合は own リポジトリ直下に書く（claude-poc-docs/ を前置しない）。

set -euo pipefail

PHASE="${1:-}"
REVIEW_JSON="${2:-}"
ISSUE=""

shift 2 || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) ISSUE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PHASE" || -z "$REVIEW_JSON" ]]; then
  echo "Usage: append-review-summary.sh <phase> <review-json-path> [--issue <N>]" >&2
  exit 1
fi
if [[ ! -f "$REVIEW_JSON" ]]; then
  echo "ERROR: review JSON not found: $REVIEW_JSON" >&2
  exit 1
fi
if [[ "$PHASE" == "implement" && -z "$ISSUE" ]]; then
  echo "ERROR: --issue is required for implement phase" >&2
  exit 1
fi

python3 - "$PHASE" "$REVIEW_JSON" "$ISSUE" << 'PY'
import json, sys, os, datetime

phase = sys.argv[1]
review_json_path = sys.argv[2]
issue = sys.argv[3] if len(sys.argv) > 3 else ""

with open(review_json_path) as f:
    r = json.load(f)

# 出力先の決定
docs_prefix = ""
if phase != "implement" and os.path.isdir("claude-poc-docs"):
    docs_prefix = "claude-poc-docs/"

if phase == "requirements":
    out_path = f"{docs_prefix}docs/requirements/レビュー結果.md"
    header = "# レビュー結果（requirements）"
elif phase == "design":
    out_path = f"{docs_prefix}docs/design/レビュー結果.md"
    header = "# レビュー結果（design）"
elif phase == "implement":
    os.makedirs("docs/test/レビュー結果", exist_ok=True)
    out_path = f"docs/test/レビュー結果/implement-issue-{issue}.md"
    header = f"# レビュー結果（implement / Issue #{issue}）"
else:
    print(f"ERROR: unknown phase: {phase}", file=sys.stderr)
    sys.exit(1)

# カウント
counts = {"BLOCK": 0, "SUGGEST": 0, "NIT": 0}
for x in r.get("findings", []):
    sev = (x.get("severity") or "").upper()
    if sev in counts:
        counts[sev] += 1

iteration = r.get("iteration", "?")
overall = r.get("overall", "FAIL")
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M")

# 新 round セクション
lines = []
lines.append(f"## Round {iteration} — {now} — overall: {overall}（BLOCK {counts['BLOCK']} / SUGGEST {counts['SUGGEST']} / NIT {counts['NIT']}）")
lines.append("")
lines.append("| 重大度 | カテゴリ | 該当 | 指摘 | 推奨対応 | 対応状況 |")
lines.append("|---|---|---|---|---|---|")

findings = r.get("findings", [])
# BLOCK → SUGGEST → NIT の順
order = {"BLOCK": 0, "SUGGEST": 1, "NIT": 2}
findings.sort(key=lambda x: order.get((x.get("severity") or "").upper(), 9))

if findings:
    for f_item in findings:
        sev = f_item.get("severity", "")
        cat = f_item.get("category", "")
        path = f_item.get("path", "")
        line_num = f_item.get("line")
        loc = f"{path}:{line_num}" if line_num else path
        msg = (f_item.get("message") or "").replace("|", "\\|").replace("\n", " ")
        fix = (f_item.get("suggested_fix") or "").replace("|", "\\|").replace("\n", " ")
        lines.append(f"| {sev} | {cat} | {loc} | {msg} | {fix} | 未対応 |")
else:
    lines.append("| — | — | — | 指摘なし | — | — |")

lines.append("")

# 検査済み観点 / 未カバー領域（P-10: 採択者が PASS の意味を読めるようにする）
checked_aspects = r.get("checked_aspects")
uncovered_areas = r.get("uncovered_areas")
if checked_aspects is not None:
    aspect_counts = {"checked": 0, "partial": 0, "not-checked": 0}
    for a in checked_aspects:
        st = a.get("status")
        if st in aspect_counts:
            aspect_counts[st] += 1
    lines.append(
        f"検査済み観点: checked {aspect_counts['checked']} / "
        f"partial {aspect_counts['partial']} / not-checked {aspect_counts['not-checked']}"
    )
    lines.append("")
    if uncovered_areas:
        lines.append("未カバー領域:")
        for ua in uncovered_areas:
            aspect = ua.get("aspect", "?")
            reason = ua.get("reason") or ua.get("note") or ""
            status = ua.get("status", "")
            suffix = f"（{status}）" if status else ""
            lines.append(f"- {aspect}{suffix}: {reason}")
        lines.append("")

new_section = "\n".join(lines)

# 既存ファイルがあれば最上部に追記、なければ新規作成
if os.path.exists(out_path):
    with open(out_path, "r") as f:
        existing = f.read()
    # ヘッダー + 説明行の直後に挿入
    marker = "> 最新 round が最上部。"
    if marker in existing:
        idx = existing.index(marker)
        end_of_marker_line = existing.index("\n", idx) + 1
        content = existing[:end_of_marker_line] + "\n" + new_section + "\n" + existing[end_of_marker_line:]
    else:
        # マーカーが見つからない場合はヘッダー直後に挿入
        content = existing.rstrip() + "\n\n" + new_section + "\n"
else:
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    preamble = f"{header}\n\n> 最新 round が最上部。各 round は機械可読 JSON を人間向けに整形したもの。\n\n"
    content = preamble + new_section + "\n"

with open(out_path, "w") as f:
    f.write(content)

print(f"OK: {out_path}")
PY
