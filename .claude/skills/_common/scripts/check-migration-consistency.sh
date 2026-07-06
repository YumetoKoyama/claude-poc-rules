#!/usr/bin/env bash
# _common/scripts/check-migration-consistency.sh
#
# 用途（RC-14 S2 / ADD-8）:
#   migration（Flyway V*.sql 等）の CREATE TABLE / ALTER TABLE のカラム定義と、
#   設計の docs/design/tables/*.md に記載されたカラム（名前・型・nullable・制約）を
#   突合し、片側にしか無いカラム・型不一致・nullable 不一致を検出する。
#
# 想定形式:
#   migration: src/main/resources/db/migration/V*.sql（または引数で指定）
#   tables md: 物理テーブル名と同じ snake_case のファイルにカラム表
#              （| カラム名 | 型 | NULL可 | ... | のような Markdown テーブル）
#
# Usage:
#   check-migration-consistency.sh [<migration-dir>] [<tables-dir>]
#     <migration-dir> : 省略時、よくある場所を自動探索
#     <tables-dir>    : 省略時 ./docs/design/tables（無ければ claude-poc-docs/... も探索）
#
# Exit:
#   0: 突合 OK（または対象不在でスキップ）
#   1: 不整合検出
#   2: 引数エラー / python3 不在

set -euo pipefail

MIG_DIR="${1:-}"
TABLES_DIR="${2:-}"

# tables-dir 自動解決
if [[ -z "$TABLES_DIR" ]]; then
  for c in "./docs/design/tables" "./claude-poc-docs/docs/design/tables"; do
    [[ -d "$c" ]] && TABLES_DIR="$c" && break
  done
fi
# migration-dir 自動解決
if [[ -z "$MIG_DIR" ]]; then
  for c in "./src/main/resources/db/migration" "./db/migration" \
           "./claude-poc-backend/src/main/resources/db/migration"; do
    [[ -d "$c" ]] && MIG_DIR="$c" && break
  done
fi

if [[ -z "$TABLES_DIR" || ! -d "$TABLES_DIR" ]]; then
  echo "INFO: tables 設計ディレクトリが見つかりません（検査をスキップ）"
  exit 0
fi
if [[ -z "$MIG_DIR" || ! -d "$MIG_DIR" ]]; then
  echo "INFO: migration ディレクトリが見つかりません（検査をスキップ）。tables: $TABLES_DIR"
  exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません" >&2
  exit 2
fi

python3 - "$MIG_DIR" "$TABLES_DIR" <<'PY'
import sys, os, re, glob

mig_dir, tables_dir = sys.argv[1], sys.argv[2]
ng = 0

# --- migration からテーブル→カラム集合を構築 ---
mig_tables = {}  # tablename -> set(colnames), and col -> (nullable)
def norm(name):
    return name.strip().strip('`"').lower()

sql_text = ""
for f in sorted(glob.glob(os.path.join(mig_dir, "V*.sql")) + glob.glob(os.path.join(mig_dir, "*.sql"))):
    with open(f, encoding="utf-8", errors="replace") as fh:
        sql_text += "\n" + fh.read()

# CREATE TABLE name ( ... );
for m in re.finditer(r"create\s+table\s+(?:if\s+not\s+exists\s+)?([`\"]?[\w]+[`\"]?)\s*\((.*?)\);",
                     sql_text, re.IGNORECASE | re.DOTALL):
    tname = norm(m.group(1))
    body = m.group(2)
    cols = {}
    # split top-level by commas (ignore commas inside parens)
    depth = 0; cur = ""; parts = []
    for ch in body:
        if ch == "(": depth += 1
        elif ch == ")": depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur); cur = ""
        else:
            cur += ch
    if cur.strip(): parts.append(cur)
    for part in parts:
        p = part.strip()
        if not p: continue
        # skip table-level constraints
        if re.match(r"(primary\s+key|foreign\s+key|unique|constraint|key|index|check)\b", p, re.IGNORECASE):
            continue
        cm = re.match(r"([`\"]?[\w]+[`\"]?)\s+(\w+)", p)
        if not cm: continue
        col = norm(cm.group(1))
        nullable = not re.search(r"not\s+null", p, re.IGNORECASE)
        cols[col] = {"nullable": nullable}
    mig_tables[tname] = cols

# ALTER TABLE name ADD COLUMN col ...
for m in re.finditer(r"alter\s+table\s+([`\"]?[\w]+[`\"]?)\s+add\s+(?:column\s+)?([`\"]?[\w]+[`\"]?)\s+(\w+)([^;]*);",
                     sql_text, re.IGNORECASE):
    tname = norm(m.group(1)); col = norm(m.group(2))
    rest = m.group(4)
    nullable = not re.search(r"not\s+null", rest, re.IGNORECASE)
    mig_tables.setdefault(tname, {})[col] = {"nullable": nullable}

if not mig_tables:
    print("INFO: migration から CREATE/ALTER TABLE を抽出できませんでした（検査をスキップ）")
    sys.exit(0)

# --- tables md からカラム集合を構築 ---
def cols_from_md(path):
    cols = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()
    # Markdown テーブル: ヘッダに カラム / column / 列名、型、NULL を探す
    header_idx = None; header = []
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("|") and re.search(r"(カラム|列名|column|name)", ln, re.IGNORECASE):
            header = [c.strip().lower() for c in ln.strip().strip("|").split("|")]
            header_idx = i
            break
    if header_idx is None:
        return cols
    def col_index(*keys):
        for k in keys:
            for j, h in enumerate(header):
                if k in h:
                    return j
        return None
    ci = col_index("カラム", "列名", "column", "name")
    ni = col_index("null", "ヌル", "必須")
    start = header_idx + 1
    if start < len(lines) and re.match(r'^\s*\|?[\s:|-]*-[\s:|-]*\|?\s*$', lines[start]):
        start += 1  # 区切り行（|---|）がある場合のみ飛ばす
    for ln in lines[start:]:
        if not ln.lstrip().startswith("|"):
            if ln.strip() == "" : continue
            break
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if ci is None or ci >= len(cells): continue
        cname = norm(cells[ci])
        if not cname or cname in ("---", ":---", "---:"): continue
        nullable = None
        if ni is not None and ni < len(cells):
            cell = cells[ni].lower()
            if any(x in cell for x in ["可", "yes", "true", "○", "nullable", "null"]):
                nullable = True
            if any(x in cell for x in ["不可", "no", "false", "×", "not null", "必須"]):
                nullable = False
        cols[cname] = {"nullable": nullable}
    return cols

md_tables = {}
for f in glob.glob(os.path.join(tables_dir, "*.md")):
    tname = norm(os.path.splitext(os.path.basename(f))[0])
    md_tables[tname] = cols_from_md(f)

# --- 突合 ---
checked = 0
for tname, mcols in mig_tables.items():
    if tname not in md_tables:
        # 設計に対応 md が無い（命名差の可能性）→ WARN
        print(f"WARN: migration のテーブル「{tname}」に対応する tables/{tname}.md がありません")
        continue
    dcols = md_tables[tname]
    if not dcols:
        print(f"WARN: tables/{tname}.md からカラム表を抽出できませんでした")
        continue
    checked += 1
    only_mig = set(mcols) - set(dcols)
    only_md = set(dcols) - set(mcols)
    for c in sorted(only_mig):
        print(f"NG: テーブル「{tname}」: migration にあるカラム「{c}」が tables/{tname}.md に未記載")
        ng = 1
    for c in sorted(only_md):
        print(f"NG: テーブル「{tname}」: 設計 tables/{tname}.md のカラム「{c}」が migration に未定義")
        ng = 1
    for c in sorted(set(mcols) & set(dcols)):
        mn = mcols[c]["nullable"]; dn = dcols[c]["nullable"]
        if dn is not None and mn != dn:
            print(f"NG: テーブル「{tname}」カラム「{c}」の nullable 不一致: migration={mn} / 設計={dn}")
            ng = 1

if checked == 0:
    print("INFO: migration と tables md の対応テーブルが突合できませんでした（命名差の可能性）")

if ng:
    print("")
    print("migration と tables/*.md のカラム整合に問題があります（S2/ADD-8）。")
    sys.exit(1)

print(f"OK: migration と tables/*.md のカラム整合が取れています（突合テーブル数: {checked}）。")
PY
