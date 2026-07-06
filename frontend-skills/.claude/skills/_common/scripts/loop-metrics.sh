#!/usr/bin/env bash
# _common/scripts/loop-metrics.sh
#
# 【P-17 対応】ループ運用の計測データを .skills-state/ から集計し、
# Markdown レポートとして出力する。改善効果（回転数・所要時間・指摘件数の推移）を
# サイクル間で定量比較できるようにする（「design-loop が遅い」等の体感を数値化）。
#
# 集計元:
#   .skills-state/<phase>/state.json            … history（stage 遷移・件数・タイムスタンプ）
#   .skills-state/<phase>/round-*-review.json   … ラウンド別の findings 件数・カテゴリ内訳
#   .skills-state/<phase>/_archive*/            … --reset でアーカイブされた過去 state（あれば）
#
# Usage:
#   loop-metrics.sh [state-root] [--out <path.md>]
#     state-root 省略時: カレントの .skills-state/
#     --out 省略時: stdout に出力
#
# Exit: 0=成功 / 2=引数・環境エラー

set -euo pipefail

ROOT=".skills-state"
OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="${2:-}"; shift 2 ;;
    *) ROOT="$1"; shift ;;
  esac
done

if [[ ! -d "$ROOT" ]]; then
  echo "ERROR: state ルートが存在しません: $ROOT" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません" >&2
  exit 2
fi

ROOT="$ROOT" OUT="$OUT" python3 <<'PY'
import json, os, sys, glob, datetime

root = os.environ["ROOT"].rstrip("/")
out = os.environ.get("OUT", "")

def parse_ts(s):
    try:
        return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    except Exception:
        return None

def fmt_dur(sec):
    if sec is None:
        return "-"
    m, s = divmod(int(sec), 60)
    h, m = divmod(m, 60)
    return f"{h}h{m:02d}m" if h else f"{m}m{s:02d}s"

lines = []
lines.append(f"# ループ運用メトリクス（{datetime.date.today().isoformat()} 生成）")
lines.append("")
lines.append(f"集計元: `{root}`（loop-metrics.sh による自動生成。P-17: 改善効果の定量比較用）")
lines.append("")

# D-04: root 自体が phase ディレクトリ（state.json を直接含む）の場合も受理する
if os.path.isfile(os.path.join(root, "state.json")):
    phase_dirs = [root]
else:
    phase_dirs = sorted(d for d in glob.glob(os.path.join(root, "*")) if os.path.isdir(d) and not os.path.basename(d).startswith("_"))
if not phase_dirs or not any(os.path.isfile(os.path.join(d, "state.json")) for d in phase_dirs):
    lines.append(f"state が見つかりません（{root} 直下にも <phase>/state.json にも state.json がありません）。")

for pd in phase_dirs:
    phase = os.path.basename(pd)
    sp = os.path.join(pd, "state.json")
    if not os.path.isfile(sp):
        continue
    try:
        with open(sp, encoding="utf-8") as f:
            s = json.load(f)
    except Exception as e:
        lines.append(f"## {phase}\n\nstate.json 読込失敗: {e}\n")
        continue

    hist = s.get("history", [])
    lines.append(f"## phase: {phase}")
    lines.append("")
    lines.append(f"- 状態: passed={s.get('passed', False)} / escalated={s.get('escalated', False)} / stage={s.get('stage','-')} / iteration={s.get('iteration','-')}/{s.get('max_iterations','-')}")

    # 経過時間（history の先頭→末尾）
    tss = [parse_ts(h.get("completed_at", "")) for h in hist]
    tss = [t for t in tss if t]
    if len(tss) >= 2:
        lines.append(f"- 全体所要時間（history 先頭→末尾）: **{fmt_dur((max(tss)-min(tss)).total_seconds())}**")
    lines.append("")

    # ラウンド別テーブル
    reviews = [h for h in hist if h.get("stage") == "review"]
    if reviews:
        lines.append("| round | BLOCK | SUGGEST | (重要) | NIT | regressed | carried | 前 stage からの経過 |")
        lines.append("|---|---|---|---|---|---|---|---|")
        prev_t = None
        for h in hist:
            t = parse_ts(h.get("completed_at", ""))
            if h.get("stage") == "review":
                bc = h.get("block_classification") or {}
                dur = fmt_dur((t - prev_t).total_seconds()) if (t and prev_t) else "-"
                lines.append(
                    f"| {h.get('iteration','-')} | {h.get('block','-')} | {h.get('suggest','-')} "
                    f"| {h.get('important_suggest','-')} | {h.get('nit','-')} "
                    f"| {bc.get('regressed','-')} | {bc.get('carried_over','-')} | {dur} |")
            if t:
                prev_t = t
        lines.append("")

    # round JSON からカテゴリ内訳（上位）と検査観点カバレッジ（P-10 連動）
    cat_count = {}
    aspects_last = None
    for rj in sorted(glob.glob(os.path.join(pd, "round-*-review.json"))):
        try:
            with open(rj, encoding="utf-8") as f:
                r = json.load(f)
        except Exception:
            continue
        for x in r.get("findings", []):
            c = (x.get("category") or "?").strip()
            cat_count[c] = cat_count.get(c, 0) + 1
        if r.get("checked_aspects") is not None:
            aspects_last = r
    if cat_count:
        top = sorted(cat_count.items(), key=lambda kv: -kv[1])[:8]
        lines.append("指摘カテゴリ上位（全ラウンド累計）: " + ", ".join(f"{c}×{n}" for c, n in top))
        lines.append("")
    if aspects_last is not None:
        ca = aspects_last.get("checked_aspects", [])
        ua = aspects_last.get("uncovered_areas", [])
        checked = sum(1 for a in ca if a.get("status") == "checked")
        lines.append(f"最終ラウンドの検査観点: checked {checked}/{len(ca)}、未カバー {len(ua)} 件")
        lines.append("")

    # escalate 理由
    esc = [h for h in hist if h.get("stage") == "escalate"]
    for h in esc:
        lines.append(f"- ESCALATE: {h.get('reason','(理由未記録)')}")
    if esc:
        lines.append("")

report = "\n".join(lines) + "\n"
if out:
    d = os.path.dirname(os.path.abspath(out))
    if d:
        os.makedirs(d, exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write(report)
    print(out)
else:
    print(report)
PY
