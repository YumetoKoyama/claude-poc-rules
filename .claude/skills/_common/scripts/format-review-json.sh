#!/usr/bin/env bash
# _common/scripts/format-review-json.sh
#
# 【P-08 / B-1 対応】review JSON の「生成」を機械化する。
# LLM は壊れない行区切り形式（TSV）で findings を吐き、本スクリプトが
# 正規 JSON を組み立てる。これにより以下を構造的に排除する:
#   - 日本語の " や \ のエスケープ漏れによる不正 JSON
#   - コンテキスト枯渇による Write 途中終了（TSV は 1 行ずつ追記できる）
#   - 複数スクリプト出力の手動マージ破損
#
# 【P-10 / U-2 対応】「PASS の説明可能性」のため、検査済み観点リスト
# （checked_aspects）と未カバー領域（uncovered_areas）を JSON に必ず含める。
# aspects TSV が渡されない場合は WARN を出し、uncovered_areas に
# 「観点リスト未提出（検査範囲不明）」を自動記録する（沈黙 PASS の禁止）。
#
# === findings TSV フォーマット（1 行 = 1 finding、タブ区切り） ===
#   列1: severity        BLOCK | SUGGEST | NIT
#   列2: category        レビュースキル定義のカテゴリ名
#   列3: path            対象ファイルパス
#   列4: line            行番号（不明なら空 or -）
#   列5: message         指摘内容（タブ・改行を含めない。強調は鉤括弧「」を使う）
#   列6: suggested_fix   修正案（同上）
#   列7: related_files   関連ファイル（; 区切り。無ければ空）
#   - 空行と # 始まりの行は無視する
#   - 決定論スクリプト（check-*.sh）の findings JSON 配列は --merge-json で
#     そのまま取り込める（手動マージ不要）
#
# === aspects TSV フォーマット（1 行 = 1 観点） ===
#   列1: aspect          観点名（レビュースキルのカテゴリ名 or チェックスクリプト名）
#   列2: status          checked | partial | not-checked
#   列3: method          script | llm | none（何で検査したか）
#   列4: note            補足（partial/not-checked の場合は理由を必須で書く）
#
# Usage:
#   format-review-json.sh <phase> <findings.tsv> <output.json> \
#     [--aspects <aspects.tsv>] [--summary <summary.txt>] [--merge-json <findings.json>]... [--suppressions <tsv>]
#     （--suppressions 省略時は <output.json> と同じディレクトリの suppressions.tsv を自動適用。D-02）
#
# Exit:
#   0: 生成成功（validate-review-json.sh も通過）
#   1: TSV 形式エラー（行番号つきで stderr に出力）
#   2: 引数エラー / ファイル不在 / python3 不在

set -euo pipefail

PHASE="${1:-}"
TSV="${2:-}"
OUT="${3:-}"
if [[ -z "$PHASE" || -z "$TSV" || -z "$OUT" ]]; then
  echo "Usage: format-review-json.sh <phase> <findings.tsv> <output.json> [--aspects f] [--summary f] [--merge-json f]..." >&2
  exit 2
fi
shift 3

ASPECTS=""
SUMMARY=""
SUPP=""
MERGE_JSONS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --aspects)      ASPECTS="${2:-}"; shift 2 ;;
    --summary)      SUMMARY="${2:-}"; shift 2 ;;
    --merge-json)   MERGE_JSONS+=("${2:-}"); shift 2 ;;
    --suppressions) SUPP="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
  esac
done

# D-02: 抑制リストの自動検出（output と同じディレクトリの suppressions.tsv）。
# 決定論 findings の偽陽性は LLM の裁量で除外せず、このリストに理由つきで宣言する。
if [[ -z "$SUPP" && -f "$(dirname "$OUT")/suppressions.tsv" ]]; then
  SUPP="$(dirname "$OUT")/suppressions.tsv"
fi

if [[ ! -f "$TSV" ]]; then
  echo "ERROR: findings TSV が存在しません: $TSV" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません" >&2
  exit 2
fi

PHASE="$PHASE" TSV="$TSV" OUT="$OUT" ASPECTS="$ASPECTS" SUMMARY="$SUMMARY" SUPP="$SUPP" \
python3 - "${MERGE_JSONS[@]}" <<'PY'
import json, os, sys, datetime

phase   = os.environ["PHASE"]

# D-02: 決定論 findings の偽陽性抑制リスト（path部分一致 \t category \t message部分一致 \t 理由 \t 承認者）
supp_rules = []
supp_path = os.environ.get("SUPP", "")
if supp_path and os.path.isfile(supp_path):
    with open(supp_path, encoding="utf-8") as f:
        for i, raw in enumerate(f, 1):
            line = raw.rstrip("\n").rstrip("\r")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            cols = (line.split("\t") + ["", "", "", "", ""])[:5]
            if not cols[3].strip():
                print(f"WARN: {supp_path}:{i}: 理由（4 列目）が空の抑制ルールは無視します", file=sys.stderr)
                continue
            supp_rules.append({"path": cols[0].strip(), "category": cols[1].strip(),
                               "message": cols[2].strip(), "reason": cols[3].strip(),
                               "approver": cols[4].strip()})
suppressed = []

def _suppress_match(x):
    for r in supp_rules:
        if r["path"] and r["path"] not in (x.get("path") or ""):
            continue
        if r["category"] and r["category"] != (x.get("category") or ""):
            continue
        if r["message"] and r["message"] not in (x.get("message") or ""):
            continue
        return r
    return None
tsv     = os.environ["TSV"]
out     = os.environ["OUT"]
aspects = os.environ.get("ASPECTS", "")
summary = os.environ.get("SUMMARY", "")
merge_jsons = sys.argv[1:]

ALLOWED_SEV = {"BLOCK", "SUGGEST", "NIT"}
ALLOWED_STATUS = {"checked", "partial", "not-checked"}
ALLOWED_METHOD = {"script", "llm", "none"}

errors = []
findings = []

# --- findings TSV ---
with open(tsv, encoding="utf-8") as f:
    for i, raw in enumerate(f, 1):
        line = raw.rstrip("\n").rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) < 6:
            errors.append(f"{tsv}:{i}: 列数不足（severity/category/path/line/message/suggested_fix の 6 列以上が必要。タブ区切りか確認）")
            continue
        sev, cat, path, lineno, msg, fix = (c.strip() for c in cols[:6])
        related = cols[6].strip() if len(cols) >= 7 else ""
        if sev.upper() not in ALLOWED_SEV:
            errors.append(f"{tsv}:{i}: severity が不正: {sev!r}（BLOCK/SUGGEST/NIT）")
            continue
        if not cat or not path or not msg or not fix:
            errors.append(f"{tsv}:{i}: category/path/message/suggested_fix は非空必須")
            continue
        fnd = {
            "severity": sev.upper(),
            "category": cat,
            "path": path,
            "message": msg,
            "suggested_fix": fix,
        }
        if lineno and lineno != "-":
            try:
                fnd["line"] = int(lineno)
            except ValueError:
                fnd["line"] = lineno  # 「12-20」等の範囲表記も許容
        if related:
            fnd["related_files"] = [r.strip() for r in related.split(";") if r.strip()]
        findings.append(fnd)

# --- 決定論スクリプトの findings JSON をマージ（重複 = path×message 一致は片方残す） ---
for mj in merge_jsons:
    if not mj:
        continue
    if not os.path.isfile(mj):
        errors.append(f"--merge-json のファイルが存在しません: {mj}")
        continue
    try:
        with open(mj, encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        errors.append(f"{mj}: JSON パース失敗（{e.msg} line {e.lineno}）")
        continue
    arr = data.get("findings") if isinstance(data, dict) else data
    if not isinstance(arr, list):
        errors.append(f"{mj}: findings 配列が見つかりません")
        continue
    seen = {(x.get("path", ""), x.get("message", "")) for x in findings}
    for x in arr:
        if not isinstance(x, dict):
            continue
        key = (x.get("path", ""), x.get("message", ""))
        if key in seen:
            continue
        seen.add(key)
        r = _suppress_match(x)
        if r is not None:
            sx = dict(x)
            sx["suppressed_by"] = {"source": os.path.basename(mj), "reason": r["reason"], "approver": r["approver"]}
            suppressed.append(sx)
            continue
        findings.append(x)

# --- aspects TSV（P-10: PASS の説明可能性） ---
checked_aspects = []
uncovered = []
if aspects:
    if not os.path.isfile(aspects):
        errors.append(f"--aspects のファイルが存在しません: {aspects}")
    else:
        with open(aspects, encoding="utf-8") as f:
            for i, raw in enumerate(f, 1):
                line = raw.rstrip("\n").rstrip("\r")
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                cols = line.split("\t")
                if len(cols) < 3:
                    errors.append(f"{aspects}:{i}: 列数不足（aspect/status/method の 3 列以上が必要）")
                    continue
                asp, status, method = (c.strip() for c in cols[:3])
                note = cols[3].strip() if len(cols) >= 4 else ""
                if status not in ALLOWED_STATUS:
                    errors.append(f"{aspects}:{i}: status が不正: {status!r}（checked/partial/not-checked）")
                    continue
                if method not in ALLOWED_METHOD:
                    errors.append(f"{aspects}:{i}: method が不正: {method!r}（script/llm/none）")
                    continue
                if status in ("partial", "not-checked") and not note:
                    errors.append(f"{aspects}:{i}: partial / not-checked の観点は note（理由）必須")
                    continue
                entry = {"aspect": asp, "status": status, "method": method}
                if note:
                    entry["note"] = note
                checked_aspects.append(entry)
                if status != "checked":
                    uncovered.append({"aspect": asp, "status": status, "reason": note})
else:
    print("WARN: aspects TSV が指定されていません。検査範囲が不明のため uncovered_areas に記録します（P-10）。", file=sys.stderr)
    uncovered.append({
        "aspect": "(全観点)",
        "status": "not-checked",
        "reason": "検査済み観点リストが提出されていない。PASS しても検査範囲は保証されない",
    })

if errors:
    print("ERROR: 入力の形式エラー:", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)

summary_text = ""
if summary and os.path.isfile(summary):
    with open(summary, encoding="utf-8") as f:
        summary_text = f.read().strip()

doc = {
    "phase": phase,
    "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "generator": "format-review-json.sh",
    "summary": summary_text,
    "findings": findings,
    "checked_aspects": checked_aspects,
    "uncovered_areas": uncovered,
}
if suppressed:
    doc["suppressed_findings"] = suppressed

outdir = os.path.dirname(os.path.abspath(out))
if outdir:
    os.makedirs(outdir, exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
    json.dump(doc, f, ensure_ascii=False, indent=2)
    f.write("\n")

b = sum(1 for x in findings if (x.get("severity") or "").upper() == "BLOCK")
s = sum(1 for x in findings if (x.get("severity") or "").upper() == "SUGGEST")
n = sum(1 for x in findings if (x.get("severity") or "").upper() == "NIT")
print(f"generated: {out} (block={b} suggest={s} nit={n} aspects={len(checked_aspects)} uncovered={len(uncovered)} suppressed={len(suppressed)})", file=sys.stderr)
print(out)
PY

# 生成物を既存バリデータで最終検証（生成の機械化 + 検証の二重化）
bash "$(dirname "${BASH_SOURCE[0]}")/validate-review-json.sh" "$OUT" >/dev/null
