#!/usr/bin/env bash
# _common/scripts/generate-rtm-skeleton.sh
#
# 【P-15 / C-4 対応】RTM（トレーサビリティマトリクス）の骨格を設計採択時点で前倒し生成する。
# 従来は製造フェーズ（/test-design-from-issue）まで RTM が存在せず、
# 「どの AC がまだテストされていないか」が横串で見えなかった。
#
# 【重要・2026-07-02 精度改善】実データ検証の結果、**AC-XXX は機能（functional/*.md）ごとの
# スコープで採番されており、グローバル一意ではない**（例: アカウント登録.md と 案件検索.md の
# 双方に AC-001 が存在する）。裸の AC-XXX を主キーにすると対応付けが混線するため、
# 本スクリプトは次の 2 部構成で生成する:
#   (1) RTM 本表 …… 主キー =「機能/AC-XXX」（機能スコープで一意化）。
#       UC は機能ファイルの関連ユースケース、BR は AC 行と同一行の引用のみ（過剰対応付けを排除）
#   (2) 画面別 AC 対応表 …… 画面 md の受け入れ条件表から SCR × AC × BR × operationId を
#       行単位で機械抽出（画面ファイル内では曖昧さが無い）。
#   【2026-07-02 追加】画面 md に「関連機能要件」（functional/〜.md への参照）があれば
#       画面→機能を機械確定し、RTM 本表の SCR / API 列を (2) から**自動転記**する。
#       参照が無い画面は従来どおり製造工程が転記する（check-wiring-fields.sh が欠落を指摘）
# TC / IT / E2E / Issue# 列は空欄（`-`）のまま置き、以後、製造・結合の各工程が埋める。
#
# --report モードで既存 RTM の未カバー集計を出力する（feature-completion-check・採択ゲート用）。
#
# Usage:
#   generate-rtm-skeleton.sh <requirements-dir> <design-dir> <output.md>   # 骨格生成（既存は .bak 退避）
#   generate-rtm-skeleton.sh --report <rtm.md>                             # 未カバー集計のみ
#
# Exit: 0=成功 / 2=引数・環境エラー

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません" >&2
  exit 2
fi

if [[ "${1:-}" == "--report" ]]; then
  RTM="${2:-}"
  if [[ -z "$RTM" || ! -f "$RTM" ]]; then
    echo "ERROR: RTM ファイルが存在しません: ${RTM:-（未指定）}" >&2
    exit 2
  fi
  RTM="$RTM" python3 <<'PY'
import os, re, sys

rtm = os.environ["RTM"]
rows = []
in_main = False
with open(rtm, encoding="utf-8") as f:
    for line in f:
        if line.startswith("## "):
            in_main = "RTM 本表" in line
            continue
        # 本表の行（第1列 = 機能/AC-XXX）のみ集計。画面別対応表は集計対象外
        if in_main and re.match(r"^\s*\|\s*[^|]*AC-\d+", line):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            rows.append(cells)

if not rows:
    print("WARN: RTM 本表の AC 行が見つかりません（表形式・セクション名「RTM 本表」を確認）", file=sys.stderr)
    sys.exit(0)

# 列順: 機能/AC | UC | BR | SCR | API | Issue# | TC | IT | E2E | 備考
def empty(v):
    return v in ("", "-", "―", "N/A")

total = len(rows)
no_tc  = [r[0] for r in rows if len(r) > 6 and empty(r[6])]
no_it  = [r[0] for r in rows if len(r) > 7 and empty(r[7])]
no_e2e = [r[0] for r in rows if len(r) > 8 and empty(r[8])]

print(f"RTM 未カバー集計: AC 総数={total}")
print(f"  TC 未対応 : {len(no_tc)} 件 " + (f"({', '.join(no_tc[:8])}{' …' if len(no_tc) > 8 else ''})" if no_tc else ""))
print(f"  IT 未対応 : {len(no_it)} 件（IT 層が無いリポジトリでは全件未対応が正常）")
print(f"  E2E 未対応: {len(no_e2e)} 件（E2E 凍結中は全件未対応が正常。凍結判断は Decision Log 参照）")
PY
  exit 0
fi

REQ_DIR="${1:-}"
DESIGN_DIR="${2:-}"
OUT="${3:-}"
if [[ -z "$REQ_DIR" || -z "$DESIGN_DIR" || -z "$OUT" ]]; then
  echo "Usage: generate-rtm-skeleton.sh <requirements-dir> <design-dir> <output.md> | --report <rtm.md>" >&2
  exit 2
fi
if [[ ! -d "$REQ_DIR" || ! -d "$DESIGN_DIR" ]]; then
  echo "ERROR: ディレクトリが存在しません: $REQ_DIR / $DESIGN_DIR" >&2
  exit 2
fi
if [[ -f "$OUT" ]]; then
  cp "$OUT" "$OUT.bak"
  echo "INFO: 既存 RTM を $OUT.bak に退避しました（手で埋めた列は骨格再生成で失われるため、再生成後に .bak から転記すること）" >&2
fi

REQ_DIR="$REQ_DIR" DESIGN_DIR="$DESIGN_DIR" OUT="$OUT" python3 <<'PY'
import os, re, glob, datetime, sys
from collections import OrderedDict

req = os.environ["REQ_DIR"].rstrip("/")
design = os.environ["DESIGN_DIR"].rstrip("/")
out = os.environ["OUT"]

ac_re  = re.compile(r"\bAC-\d{3}\b")
uc_re  = re.compile(r"\bUC-\d{3}\b")
br_re  = re.compile(r"\bBR-\d{3}\b")
scr_re = re.compile(r"\bSCR-\d{3}(?:-\d{2})?\b")
op_def_re = re.compile(r"^\s*operationId:\s*([A-Za-z][A-Za-z0-9_]*)\s*$")

def read(p):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except Exception:
        return ""

# --- api/*.yaml の operationId 集合（画面別対応表の抽出に使用） ---
all_ops = set()
for y in glob.glob(os.path.join(design, "api", "*.yaml")) + glob.glob(os.path.join(design, "api", "*.yml")):
    for line in read(y).splitlines():
        m = op_def_re.match(line)
        if m:
            all_ops.add(m.group(1))

# --- (1) RTM 本表: functional/*.md から 機能×AC を抽出（同一行の BR のみ対応付け） ---
main_rows = OrderedDict()   # (feature, ac) -> {"uc": set, "br": set}
warn_dup_ac = {}

func_files = sorted(glob.glob(os.path.join(req, "functional", "*.md")))
if not func_files:
    print(f"WARN: {os.path.join(req,'functional')} に機能要件ファイルがありません", file=sys.stderr)

for fp in func_files:
    feature = os.path.splitext(os.path.basename(fp))[0]
    text = read(fp)
    file_ucs = sorted(set(uc_re.findall(text)))   # 機能ファイル全体の関連 UC（通常 1〜2 件）
    for line in text.splitlines():
        for ac in ac_re.findall(line):
            key = (feature, ac)
            e = main_rows.setdefault(key, {"uc": set(file_ucs), "br": set()})
            e["br"].update(br_re.findall(line))   # AC と同一行の BR のみ（過剰対応付け排除）
            warn_dup_ac.setdefault(ac, set()).add(feature)

# AC のグローバル一意性チェック（実データでは機能スコープ採番のため重複が正常だが、明示する）
dup = {ac: fs for ac, fs in warn_dup_ac.items() if len(fs) > 1}
if dup:
    print(f"INFO: {len(dup)} 個の AC-ID が複数機能で再利用されています（機能スコープ採番）。"
          f"RTM は「機能/AC」で一意化しました。例: " +
          "、".join(f"{ac}({len(fs)}機能)" for ac, fs in list(dup.items())[:5]), file=sys.stderr)

# --- (2) 画面別 AC 対応表: screens/SCR-*.md の受け入れ条件表から行単位で抽出 ---
screen_rows = []   # (scr, ac, br_str, ops_str, feature or None)
func_ref_re = re.compile(r"functional/([^/\\)\s`]+)\.md")
features_known = {os.path.splitext(os.path.basename(fp))[0] for fp in func_files}
screens_without_ref = []
for smd in sorted(glob.glob(os.path.join(design, "screens", "SCR-*.md"))):
    fname = os.path.basename(smd)
    m = scr_re.search(fname)
    scr = m.group(0) if m else fname
    text = read(smd)
    # 画面→機能の機械確定（「関連機能要件」欄の functional/〜.md 参照。複数可）
    scr_features = [f for f in func_ref_re.findall(text) if f in features_known]
    if not scr_features:
        screens_without_ref.append(scr)
    for line in text.splitlines():
        # 表の行で第 1 セルが AC-XXX のものだけを対象（受け入れ条件表の行）
        cells = [c.strip() for c in line.strip().strip("|").split("|")] if line.strip().startswith("|") else []
        if not cells or not ac_re.fullmatch(cells[0] or ""):
            continue
        ac = cells[0]
        brs = sorted(set(br_re.findall(line)))
        ops = sorted({w for w in re.findall(r"\b[a-z][A-Za-z0-9]{2,}\b", line) if w in all_ops})
        screen_rows.append((scr, ac, ", ".join(brs) or "-", ", ".join(ops) or "-", scr_features))
        # 自動転記: 画面が機能参照を持つ場合、該当（機能, AC）の本表行に SCR / API を積む
        for feat in scr_features:
            key = (feat, ac)
            if key in main_rows:
                main_rows[key].setdefault("scr", set()).add(scr)
                main_rows[key].setdefault("api", set()).update(ops)

def cell(s):
    return ", ".join(sorted(s)) if s else "-"

lines = []
lines.append("# RTM（トレーサビリティマトリクス）")
lines.append("")
lines.append(f"生成: {datetime.date.today().isoformat()} / generate-rtm-skeleton.sh（設計採択時の骨格前倒し生成・P-15）")
lines.append("")
lines.append("運用ルール:")
lines.append("")
lines.append("- **AC-XXX は機能ごとのスコープで採番されている**（グローバル一意でない）ため、本表の主キーは「機能/AC」。他文書から参照する際も必ず機能名で修飾する。")
lines.append("- 本表の UC は機能ファイルの関連ユースケース、BR は AC 定義行と同一行の引用のみ（機械抽出）。誤りは手で修正してよい。")
lines.append("- SCR / API 列は、画面 md の「関連機能要件」（functional/〜.md 参照）がある画面については**自動転記済み**。参照が無い画面の分は「画面別 AC 対応表」（下部）を根拠に製造工程が転記する（参照の追加を推奨。check-wiring-fields.sh が欠落を指摘する）。")
lines.append("- **TC / IT / E2E / Issue# 列は各工程が埋める**: TC・Issue#=製造（/test-design-from-issue）、IT=結合テスト工程、E2E=E2E 工程（凍結中）。")
lines.append("- 未カバー集計は `generate-rtm-skeleton.sh --report <本ファイル>` で機械確認できる。")
lines.append("- 意図的にテストしない AC は `-` のままにせず「対象外（Decision Log の D-ID）」を記入する。")
lines.append("")
lines.append("## RTM 本表（主キー: 機能/AC）")
lines.append("")
lines.append("| 機能/AC | UC | BR | SCR | API operationId | Issue# | TC-XXX | IT-XXX | E2E-XXX | 備考 |")
lines.append("|---|---|---|---|---|---|---|---|---|---|")
auto_filled = 0
for (feature, ac), e in main_rows.items():
    scr_c = cell(e.get("scr", set()))
    api_c = cell(e.get("api", set()))
    if scr_c != "-" or api_c != "-":
        auto_filled += 1
    lines.append(f"| {feature}/{ac} | {cell(e['uc'])} | {cell(e['br'])} | {scr_c} | {api_c} | - | - | - | - | |")
lines.append("")
lines.append(f"AC 総数: {len(main_rows)}（生成時点で TC/IT/E2E は全件未対応 = これが「見える化された未カバー」）")
lines.append("")
lines.append("## 画面別 AC 対応表（画面 md の受け入れ条件表から機械抽出・転記用の根拠）")
lines.append("")
lines.append("> AC は**画面ローカルの引用**（画面が属する機能のスコープ）。本表の行を根拠に、上の RTM 本表の SCR / API 列を製造工程で埋める。")
lines.append("")
lines.append("| SCR | AC（画面内引用） | BR（同一行） | operationId（同一行） | 機能（関連機能要件） |")
lines.append("|---|---|---|---|---|")
for scr, ac, brs, ops, feats in screen_rows:
    feat_c = ", ".join(feats) if feats else "（関連機能要件の参照なし）"
    lines.append(f"| {scr} | {ac} | {brs} | {ops} | {feat_c} |")
lines.append("")

d = os.path.dirname(os.path.abspath(out))
if d:
    os.makedirs(d, exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

if screens_without_ref:
    print(f"INFO: 関連機能要件（functional/〜.md 参照）の無い画面 {len(screens_without_ref)} 件: "
          + ", ".join(screens_without_ref[:10]) + (" …" if len(screens_without_ref) > 10 else "")
          + "（これらの SCR/API 列は自動転記されない。画面 md への参照追記を推奨）", file=sys.stderr)
print(f"generated: {out} (機能×AC={len(main_rows)}, 自動転記={auto_filled}行, 画面別AC行={len(screen_rows)})", file=sys.stderr)
print(out)
PY
