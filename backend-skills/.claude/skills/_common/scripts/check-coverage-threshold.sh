#!/usr/bin/env bash
# _common/scripts/check-coverage-threshold.sh
#
# 用途（RC-14 S2 / ADD-3 / RC-07）:
#   JaCoCo XML（backend）/ Istanbul JSON（frontend）からカバレッジ値を抽出し、
#   技術スタック確定表（*-00-stack.md）に記載された閾値と機械比較する。
#   閾値未達なら exit 1（review-implementation の coverage BLOCK と対応）。
#
# 確定表からの閾値抽出:
#   *-00-stack.md の本文中で「カバレッジ」近傍に現れる「<指標> ... NN%」を読む。
#   - backend: INSTRUCTION（命令網羅）/ BRANCH（分岐網羅）の閾値
#   - frontend: LINE（行網羅）の閾値
#   閾値が見つからない場合は既定 0%（=未達判定しない）とし WARN を出す。
#
# Usage:
#   check-coverage-threshold.sh <backend|frontend> [<report-path>] [<stack-md>]
#     <report-path> : 省略時、よくある場所を自動探索
#     <stack-md>    : 省略時、.claude/rules/*-00-stack.md を自動探索
#
# Exit:
#   0: 閾値充足（またはレポート/閾値不在でスキップ・WARN）
#   1: 閾値未達
#   2: 引数エラー / python3 不在

set -euo pipefail

REPO_TYPE="${1:-}"
REPORT="${2:-}"
STACK_MD="${3:-}"

case "$REPO_TYPE" in
  backend|frontend) ;;
  *) echo "ERROR: usage: check-coverage-threshold.sh <backend|frontend> [report] [stack-md]" >&2; exit 2 ;;
esac
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません" >&2; exit 2
fi

# stack md 自動探索
if [[ -z "$STACK_MD" ]]; then
  shopt -s nullglob
  for c in ./.claude/rules/*-00-stack.md ./claude-poc-$REPO_TYPE/.claude/rules/*-00-stack.md; do
    [[ -f "$c" ]] && STACK_MD="$c" && break
  done
  shopt -u nullglob
fi

# report 自動探索
if [[ -z "$REPORT" ]]; then
  if [[ "$REPO_TYPE" == "backend" ]]; then
    for c in ./target/site/jacoco/jacoco.xml ./build/reports/jacoco/test/jacocoTestReport.xml \
             ./claude-poc-backend/target/site/jacoco/jacoco.xml; do
      [[ -f "$c" ]] && REPORT="$c" && break
    done
  else
    for c in ./coverage/coverage-final.json ./coverage/coverage-summary.json \
             ./claude-poc-frontend/coverage/coverage-summary.json; do
      [[ -f "$c" ]] && REPORT="$c" && break
    done
  fi
fi

if [[ -z "$REPORT" || ! -f "$REPORT" ]]; then
  echo "INFO: カバレッジレポートが見つかりません（$REPO_TYPE）。テスト実行後に再検査してください（検査をスキップ）"
  exit 0
fi

python3 - "$REPO_TYPE" "$REPORT" "${STACK_MD:-}" <<'PY'
import sys, re, json
import xml.etree.ElementTree as ET

repo, report, stack_md = sys.argv[1], sys.argv[2], sys.argv[3]

# --- 閾値抽出 ---
thresholds = {}  # metric -> percent
if stack_md:
    try:
        with open(stack_md, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        text = ""
    # カバレッジ文脈の行のみを対象にして地の文の NN% 誤抽出を防ぐ
    cov_lines = [ln for ln in text.splitlines() if re.search(r"カバレッジ|coverage|JaCoCo|jacoco|網羅|閾値|INSTRUCTION|BRANCH|Istanbul|statement|ステートメント|命令|分岐", ln, re.IGNORECASE)]
    cov_text = "\n".join(cov_lines) if cov_lines else text
    # 「カバレッジ」近傍を対象に、INSTRUCTION/BRANCH/LINE と NN% を拾う
    for label, key in [("命令", "INSTRUCTION"), ("instruction", "INSTRUCTION"),
                       ("分岐", "BRANCH"), ("branch", "BRANCH"),
                       ("行", "LINE"), ("line", "LINE"), ("ライン", "LINE")]:
        for m in re.finditer(rf"{label}[^%\n]{{0,20}}?(\d{{1,3}})\s*%", cov_text, re.IGNORECASE):
            v = int(m.group(1))
            if 0 <= v <= 100:
                thresholds[key] = max(thresholds.get(key, 0), v)
    # 汎用「カバレッジ ... NN%」（指標未特定）→ LINE/INSTRUCTION 既定に流用
    if not thresholds:
        for m in re.finditer(r"カバレッジ[^%\n]{0,30}?(\d{1,3})\s*%", cov_text):
            v = int(m.group(1))
            if 0 <= v <= 100:
                thresholds["LINE" if repo == "frontend" else "INSTRUCTION"] = v

# --- 実測値抽出 ---
actual = {}
if repo == "backend":
    try:
        tree = ET.parse(report)
        root = tree.getroot()
        # report 直下の <counter type="INSTRUCTION" missed=".." covered=".."/>
        for c in root.findall("counter"):
            t = c.get("type"); missed = int(c.get("missed", 0)); covered = int(c.get("covered", 0))
            total = missed + covered
            if total > 0:
                actual[t] = round(covered * 100.0 / total, 2)
    except ET.ParseError as e:
        print(f"ERROR: JaCoCo XML のパースに失敗: {e}", file=sys.stderr); sys.exit(2)
else:
    try:
        with open(report, encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"ERROR: カバレッジ JSON のパースに失敗: {e}", file=sys.stderr); sys.exit(2)
    # coverage-summary.json: total.lines.pct
    if isinstance(data, dict) and "total" in data and isinstance(data["total"], dict):
        tot = data["total"]
        if "lines" in tot and "pct" in tot["lines"]:
            actual["LINE"] = float(tot["lines"]["pct"])
        if "branches" in tot and "pct" in tot["branches"]:
            actual["BRANCH"] = float(tot["branches"]["pct"])
    else:
        # coverage-final.json: ファイル別。s（statement）から行カバレッジを近似集計
        covered = total = 0
        for fdata in (data.values() if isinstance(data, dict) else []):
            s = fdata.get("s", {}) if isinstance(fdata, dict) else {}
            for hit in s.values():
                total += 1
                if hit and hit > 0:
                    covered += 1
        if total > 0:
            actual["LINE"] = round(covered * 100.0 / total, 2)

if not actual:
    print("INFO: レポートからカバレッジ値を抽出できませんでした（検査をスキップ）")
    sys.exit(0)

print(f"INFO: 実測カバレッジ ({repo}): " + ", ".join(f"{k}={v}%" for k, v in sorted(actual.items())))
if not thresholds:
    print(f"WARN: 確定表から閾値を抽出できませんでした（{stack_md or 'stack md 不在'}）。未達判定はスキップします")
    sys.exit(0)
print("INFO: 閾値: " + ", ".join(f"{k}>={v}%" for k, v in sorted(thresholds.items())))

ng = 0
for metric, thr in thresholds.items():
    if metric in actual:
        if actual[metric] + 1e-9 < thr:
            print(f"NG: {metric} カバレッジ {actual[metric]}% が閾値 {thr}% を下回っています")
            ng = 1
    else:
        print(f"WARN: 閾値のある指標 {metric} が実測に存在しません（レポート種別を確認）")

if ng:
    print("")
    print("カバレッジが確定表の閾値に未達です（S2/ADD-3/RC-07）。")
    sys.exit(1)
print("OK: カバレッジが確定表の閾値を満たしています。")
PY
