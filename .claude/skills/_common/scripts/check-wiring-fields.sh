#!/usr/bin/env bash
# _common/scripts/check-wiring-fields.sh
#
# 【P-12 / A-1 残課題対応】画面 md ⇔ API YAML の「全項目」突合（data-sufficiency の網羅度強化）。
# 2026-07-02 の design-amendment（registerTenant への loginId/address 追加漏れ）の再発防止。
#
# 従来の check-wiring / vertical-trace が「operationId の実在」を見るのに対し、
# 本スクリプトは「項目（フィールド）単位」で次を検査する:
#   (1) 画面 md の項目表（表示項目・入力項目・データ項目）の各行に
#       供給元/送信先の記載（operationId または operationId.field）があるか
#   (2) 参照された operationId が api/*.yaml に実在するか
#   (3) 行に書かれたフィールド名（英字 camelCase）が、参照先 YAML 内に出現するか
#       —— 出現しなければ「設計書間の項目欠落」候補（registerTenant 型の欠陥）
#
# 検査は表示（レスポンス）方向だけでなく入力（リクエスト）方向も対象とする。
#
# 限界（正直に明記。ここは LLM レビューで補完する）:
#   - YAML の構造解析はせず「フィールド名文字列の出現」で判定する（誤検知より見逃し防止を優先し、
#     ネスト位置の誤りまでは検出しない）
#   - 項目表のセクション見出し・列構成が既定パターンから大きく外れる画面 md は
#     not-checked として報告する（沈黙スキップしない）
#
# Usage:
#   check-wiring-fields.sh <design-dir>       # 例: docs/design/ または claude-poc-docs/docs/design/
#
# 出力: findings JSON 配列（severity/path/line/category/message/suggested_fix）を stdout に出力。
#       検査サマリ（検査画面数・not-checked 一覧）を stderr に出力。
# Exit: 0=実行成功（findings の有無に関わらず） / 2=引数・環境エラー

set -euo pipefail

DESIGN_DIR="${1:-docs/design}"
if [[ ! -d "$DESIGN_DIR" ]]; then
  echo "ERROR: design ディレクトリが存在しません: $DESIGN_DIR" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません" >&2
  exit 2
fi

DESIGN_DIR="$DESIGN_DIR" python3 <<'PY'
import json, os, re, sys, glob

design = os.environ["DESIGN_DIR"].rstrip("/")
screens_dir = os.path.join(design, "screens")
api_dir = os.path.join(design, "api")

findings = []
summary = {"screens_checked": 0, "screens_not_checked": [], "rows_checked": 0}

# --- api/*.yaml から operationId と本文テキストを収集 ---
op_re = re.compile(r"^\s*operationId:\s*([A-Za-z][A-Za-z0-9_]*)\s*$")
yaml_ops = {}    # operationId -> yaml path
yaml_text = {}   # yaml path -> full text
for y in sorted(glob.glob(os.path.join(api_dir, "*.yaml")) + glob.glob(os.path.join(api_dir, "*.yml"))):
    try:
        with open(y, encoding="utf-8") as f:
            t = f.read()
    except Exception:
        continue
    yaml_text[y] = t
    for m in op_re.finditer(t):
        pass
    for line in t.splitlines():
        m = op_re.match(line)
        if m:
            yaml_ops[m.group(1)] = y

if not yaml_ops:
    print(f"WARN: {api_dir} に operationId が見つかりません（API 設計未着手なら本チェックは不成立）", file=sys.stderr)

# --- 画面 md の項目表を走査 ---
# 対象セクション見出し（この配下の markdown テーブルを項目表とみなす）
# 実データの見出し（出力・表示内容 / 入力・操作）と汎用名の両方に対応
disp_sec_re = re.compile(r"^#{2,4}\s*.*(出力・表示内容|表示項目|データ項目|項目定義)")
input_sec_re = re.compile(r"^#{2,4}\s*.*(入力・操作|入力項目|フォーム項目)")
any_sec_re = re.compile(r"^#{1,4}\s")
row_re = re.compile(r"^\s*\|(.+)\|\s*$")
sep_re = re.compile(r"^\s*\|[\s:|-]+\|\s*$")
# 供給元/送信先の記載: operationId 単独 or operationId.field
opfield_re = re.compile(r"\b([a-z][A-Za-z0-9]*)\s*\.\s*([A-Za-z][A-Za-z0-9_\[\].]*)")
# 除外語（画面 md 内で頻出する camelCase 以外の英字トークン誤検知を避けるための当たり判定は
# 「yaml_ops に実在する名前」でのみ operationId とみなす方式にする）

screen_files = sorted(glob.glob(os.path.join(screens_dir, "SCR-*.md")))
if not screen_files:
    print(f"WARN: {screens_dir} に SCR-*.md がありません", file=sys.stderr)

for smd in screen_files:
    with open(smd, encoding="utf-8") as f:
        lines = f.readlines()
    section = None  # None | "display" | "input"
    header_cells = []
    table_rows = 0
    checked_rows = 0
    input_rows_no_ref = []  # (line, 項目名) 送信先フィールド未記載の入力項目
    for idx, raw in enumerate(lines, 1):
        line = raw.rstrip("\n")
        if any_sec_re.match(line):
            if disp_sec_re.match(line):
                section = "display"
            elif input_sec_re.match(line):
                section = "input"
            else:
                section = None
            header_cells = []
            continue
        if section is None:
            continue
        m = row_re.match(line)
        if not m:
            continue
        if sep_re.match(line):
            continue
        cells = [c.strip() for c in m.group(1).split("|")]
        if not header_cells:
            header_cells = cells
            continue
        table_rows += 1
        row_text = " ".join(cells)
        item_name = cells[0] if cells else ""
        if not item_name or item_name in ("項目", "-", "―"):
            continue

        # (1) 供給元/送信先の記載有無
        refs = opfield_re.findall(row_text)
        op_tokens = [w for w in re.findall(r"\b[a-z][A-Za-z0-9]{2,}\b", row_text) if w in yaml_ops]
        if not refs and not op_tokens:
            # 固定文言・ラベル等は「固定」「静的」「なし」等の明記があれば許容
            if re.search(r"(固定|静的|リテラル|画面内|なし|N/A|遷移パラメータ|URL|ローカル)", row_text):
                checked_rows += 1
                continue
            if section == "input":
                # 実データの「入力・操作」表には送信先 API 列が無いのが常態のため、
                # 行単位ではなく画面単位で集約して指摘する（registerTenant 型欠陥の構造原因）
                input_rows_no_ref.append((idx, item_name))
            else:
                findings.append({
                    "severity": "SUGGEST",
                    "category": "data-sufficiency",
                    "path": os.path.relpath(smd),
                    "line": idx,
                    "message": f"表示項目「{item_name}」に供給元 API（operationId.フィールド）の記載が無い。固定値なら「固定」と明記が必要",
                    "suggested_fix": "データ源欄に operationId.フィールド名 を明記するか、固定値/画面内完結であることを明記する",
                })
            continue

        # (2) operationId 実在チェック + (3) フィールド出現チェック
        row_ok = True
        for op, field in refs:
            if op not in yaml_ops:
                findings.append({
                    "severity": "BLOCK",
                    "category": "data-sufficiency",
                    "path": os.path.relpath(smd),
                    "line": idx,
                    "message": f"項目「{item_name}」が参照する operationId「{op}」が {api_dir}/*.yaml に存在しない",
                    "suggested_fix": "operationId の誤記を修正するか、API 設計に当該操作を追加する",
                })
                row_ok = False
                continue
            base_field = re.split(r"[\[\].]", field)[0]
            if base_field and base_field not in yaml_text[yaml_ops[op]]:
                findings.append({
                    "severity": "BLOCK",
                    "category": "data-sufficiency",
                    "path": os.path.relpath(smd),
                    "line": idx,
                    "message": f"項目「{item_name}」のフィールド「{op}.{field}」が {os.path.basename(yaml_ops[op])} に出現しない（設計書間の項目欠落の可能性。registerTenant 型欠陥の再発パターン）",
                    "suggested_fix": f"{os.path.basename(yaml_ops[op])} の該当スキーマにフィールド「{base_field}」を追加するか、画面 md の参照を修正する",
                    "related_files": [os.path.relpath(yaml_ops[op])],
                })
                row_ok = False
        if row_ok:
            checked_rows += 1

    # 【2026-07-02 追加】画面→機能の機械確定用の「関連機能要件」参照（functional/〜.md）の有無
    if not re.search(r"functional/[^/\\)\s`]+\.md", "".join(lines)):
        findings.append({
            "severity": "SUGGEST",
            "category": "data-sufficiency",
            "path": os.path.relpath(smd),
            "line": 1,
            "message": "画面 md に「関連機能要件」（docs/requirements/functional/〜.md への参照）が無い。AC-XXX は機能スコープ採番のため、参照が無いとこの画面の AC がどの機能の AC か機械確定できず、RTM の SCR/API 自動転記も働かない",
            "suggested_fix": "基本情報に「関連機能要件: docs/requirements/functional/[機能名].md」を追記する（テンプレート overview-screens.md 準拠）",
        })
    if input_rows_no_ref:
        names = "、".join(n for _, n in input_rows_no_ref[:8]) + ("…" if len(input_rows_no_ref) > 8 else "")
        ops_in_file = sorted({w for w in re.findall(r"\b[a-z][A-Za-z0-9]{2,}\b", "".join(lines)) if w in yaml_ops})
        findings.append({
            "severity": "SUGGEST",
            "category": "data-sufficiency",
            "path": os.path.relpath(smd),
            "line": input_rows_no_ref[0][0],
            "message": f"入力項目 {len(input_rows_no_ref)} 件（{names}）に送信先（operationId.リクエストフィールド）の明記が無い。入力項目→リクエストスキーマの対応が設計書上で検証できない（registerTenant への項目追加漏れ＝2026-07-02 design-amendment の構造原因）",
            "suggested_fix": "「入力・操作」表に「送信先（operationId.フィールド）」列を追加し、書込み API（" + (", ".join(ops_in_file[:5]) or "該当 operationId") + " 等）のリクエストスキーマと 1 行ずつ対応させる",
        })
    if table_rows == 0:
        summary["screens_not_checked"].append(os.path.relpath(smd))
    else:
        summary["screens_checked"] += 1
        summary["rows_checked"] += checked_rows

# --- サマリ（P-10: 何を検査し何を検査しなかったかを常に報告） ---
print(f"INFO: 項目突合 完了 screens_checked={summary['screens_checked']} rows_checked={summary['rows_checked']}", file=sys.stderr)
if summary["screens_not_checked"]:
    print("WARN: 項目表を検出できず not-checked の画面（LLM レビューで補完すること）:", file=sys.stderr)
    for p in summary["screens_not_checked"]:
        print(f"  - {p}", file=sys.stderr)
        findings.append({
            "severity": "NIT",
            "category": "data-sufficiency",
            "path": p,
            "message": "項目表（表示項目/入力項目セクションの markdown テーブル）を機械検出できなかった。本画面の項目突合は機械検査されていない",
            "suggested_fix": "画面 md の項目定義を「## 表示項目」「## 入力項目」配下の表形式に整えるか、LLM レビューで手動突合する",
        })

print(json.dumps(findings, ensure_ascii=False, indent=2))
PY
