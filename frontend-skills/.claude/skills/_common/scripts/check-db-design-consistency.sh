#!/usr/bin/env bash
# _common/scripts/check-db-design-consistency.sh
#
# 用途（BE↔DB 観点の設計フェーズ前倒し。FE↔BE 界面契約と対称化）:
#   設計成果物「だけ」で BE↔DB 整合を機械検証する（migration / Entity が未生成でも動く）。
#   Entity↔migration の三者整合は製造フェーズ（check-migration-consistency.sh / design_mismatch）に残し、
#   本スクリプトは「設計だけで閉じる」次の 2 系統を担当する。
#     (1) db-schema-completeness : tables/*.md 内部の完全性
#         主キー(PK) / 全カラムの型 / 文字列カラムの桁 / nullable / 一意制約 / インデックス方針 /
#         並行制御列(version)の要否 — の記載有無（不要なら「なし」と明記されているか）
#     (2) db-contract            : tables/*.md ↔ api/*.yaml の型・桁・required・enum 整合
#     (3) db-sequence-consistency: sequences/*.md の SQL（INSERT/UPDATE 列・INTERVAL 値）↔ tables/*.md
#                                  ※ md_tables（本ファイルのテーブル解析）を再利用し、解析器を重複させない
#         （PyYAML があれば実施。無ければ INFO でスキップし (1) のみ実行）
#
# 想定形式:
#   tables md : 物理テーブル名と同じ snake_case のファイル名。カラム表（| カラム名 | 型 | NULL | ... |）。
#   api yaml  : docs/design/api/*.yaml（OpenAPI 3.1）。components.schemas.*.properties。
#
# Usage:
#   check-db-design-consistency.sh [<design-dir>]
#     <design-dir> : 省略時 ./docs/design（無ければ ./claude-poc-docs/docs/design を自動探索）
#
# Exit:
#   0: 整合 OK（または対象不在でスキップ）
#   1: 不整合検出（findings を JSON 配列で標準出力）
#   2: 引数エラー / python3 不在
#
# 出力:
#   不整合がある場合、findings を JSON 配列（severity/path/line/category/message/suggested_fix）で
#   標準出力に出す。review-design はこれを自分の review JSON に merge する（check-truncation.sh と同じ作法）。

set -euo pipefail

DESIGN_DIR="${1:-}"
if [[ -z "$DESIGN_DIR" ]]; then
  for c in "./docs/design" "./claude-poc-docs/docs/design"; do
    [[ -d "$c" ]] && DESIGN_DIR="$c" && break
  done
fi

if [[ -z "$DESIGN_DIR" || ! -d "$DESIGN_DIR/tables" ]]; then
  echo "INFO: tables 設計ディレクトリが見つかりません（検査をスキップ）"
  exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません" >&2
  exit 2
fi

python3 - "$DESIGN_DIR" <<'PY'
import sys, os, re, glob, json

design = sys.argv[1]
tables_dir = os.path.join(design, "tables")
api_dir    = os.path.join(design, "api")
findings = []

def norm(name):
    return name.strip().strip('`"').lower()

# ----------------------------------------------------------------------------
# tables/*.md のカラム表を解析（check-migration-consistency.sh と同じ抽出方針 + 型/桁）
# ----------------------------------------------------------------------------
def parse_table_md(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()
    text = "".join(lines)
    cols = {}          # colname -> {type, length, nullable, raw}
    header_idx = None; header = []
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("|") and re.search(r"(カラム|列名|column|name)", ln, re.IGNORECASE):
            header = [c.strip().lower() for c in ln.strip().strip("|").split("|")]
            header_idx = i
            break
    if header_idx is None:
        return cols, text, False  # カラム表なし

    def col_index(*keys):
        for k in keys:
            for j, h in enumerate(header):
                if k in h:
                    return j
        return None
    ci = col_index("カラム", "列名", "column", "name")
    ti = col_index("型", "type", "データ型")
    ni = col_index("null", "ヌル", "必須")

    start = header_idx + 1
    if start < len(lines) and re.match(r'^\s*\|?[\s:|-]*-[\s:|-]*\|?\s*$', lines[start]):
        start += 1  # 区切り行（|---|）
    for ln in lines[start:]:
        if not ln.lstrip().startswith("|"):
            if ln.strip() == "":
                continue
            break
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if ci is None or ci >= len(cells):
            continue
        cname = norm(cells[ci])
        if not cname or cname in ("---", ":---", "---:"):
            continue
        typ = cells[ti].strip() if (ti is not None and ti < len(cells)) else ""
        length = None
        lm = re.search(r"\(\s*(\d+)\s*\)", typ)
        if lm:
            length = int(lm.group(1))
        nullable = None
        if ni is not None and ni < len(cells):
            cell = cells[ni].strip().lower()
            # NOT NULL / 不可 系を先に判定（"not null" は "null" を含むため順序が重要）
            if ("not null" in cell) or (cell in ("×", "no", "false", "不可", "必須")) or ("不可" in cell):
                nullable = False
            elif (cell in ("null", "yes", "true", "○", "可", "nullable")) \
                 or any(x in cell for x in ["可", "yes", "true", "○", "nullable"]):
                nullable = True
        cols[cname] = {"type": typ, "length": length, "nullable": nullable, "raw": ln.strip()}
    return cols, text, True

# 必須トピック（無ければ「なし」と明記されているはず＝キーワード自体は出現する）
REQUIRED_TOPICS = {
    "主キー(PK)":          r"(主キー|primary\s*key|\bpk\b)",
    "一意制約":            r"(一意|unique)",
    "インデックス方針":    r"(インデックス|index|索引)",
    "並行制御列(version)": r"(version|楽観|悲観|ロック|並行|並列)",
}

md_tables = {}  # tname -> cols
for path in sorted(glob.glob(os.path.join(tables_dir, "*.md"))):
    base = os.path.splitext(os.path.basename(path))[0]
    tname = norm(base)
    cols, text, has_table = parse_table_md(path)
    md_tables[tname] = cols

    # (1) db-schema-completeness
    if not has_table or not cols:
        findings.append(dict(
            severity="BLOCK", path=path, line=1, category="db-schema-completeness",
            message="「カラム表（カラム名・型・NULL）が抽出できない。テーブル定義が不完全」",
            suggested_fix="カラムごとに 型・桁・NULL を持つ Markdown 表を記載する"))
    else:
        for cname, info in cols.items():
            t = info["type"]
            if re.search(r"(varchar|char|文字|nvarchar)", t, re.IGNORECASE) and info["length"] is None and "text" not in t.lower():
                findings.append(dict(
                    severity="BLOCK", path=path, line=1, category="db-schema-completeness",
                    message=f"「カラム {cname} の文字列型に桁指定が無い: {t or '(型未記載)'}」",
                    suggested_fix="VARCHAR(n) のように桁を明記する（可変長 TEXT は型名で明示）"))
            if not t:
                findings.append(dict(
                    severity="BLOCK", path=path, line=1, category="db-schema-completeness",
                    message=f"「カラム {cname} の型が未記載」",
                    suggested_fix="型を明記する"))
            if info["nullable"] is None:
                findings.append(dict(
                    severity="BLOCK", path=path, line=1, category="db-schema-completeness",
                    message=f"「カラム {cname} の NULL/NOT NULL が判定できない」",
                    suggested_fix="NULL 列に NULL/NOT NULL（可/不可）を明記する"))
        for topic, pat in REQUIRED_TOPICS.items():
            if not re.search(pat, text, re.IGNORECASE):
                findings.append(dict(
                    severity="BLOCK", path=path, line=1, category="db-schema-completeness",
                    message=f"「{topic} に関する記載が無い（不要なら『なし』と明記が必要）」",
                    suggested_fix=f"{topic} の方針を明記する（無ければ『なし』と書く）"))

# ----------------------------------------------------------------------------
# (2) db-contract : tables ↔ api の型/桁/enum 突合（PyYAML があれば実施）
# ----------------------------------------------------------------------------
def collect_api_props(api_dir):
    """フィールド -> {maxLength:set, enum:set, types:set} を 2 系統で集約する:
      - props        : 全 YAML 横断のグローバル集約（従来と同じ。対応リソースが特定できない表の fallback 用）
      - by_resource  : YAML ファイル stem（=リソース名）別の集約。
    同名フィールドが複数リソースで別桁を正当に持つ場合（例: application.note=500 / job.note=1000）に、
    グローバル集約だけで突合すると cross-resource の桁不一致を誤検知する（D-* / MEMORY.md 記録の偽陽性）。
    テーブル md と同名の API リソースがあれば by_resource を優先突合し、この誤検知を排除する。
    戻り値: (props, by_resource)。PyYAML 不在時は (None, None)。
    """
    try:
        import yaml  # PyYAML
    except Exception:
        return None, None
    props = {}
    by_resource = {}
    if not os.path.isdir(api_dir):
        return {}, {}
    def walk(schema, bucket):
        if not isinstance(schema, dict):
            return
        p = schema.get("properties")
        if isinstance(p, dict):
            for fname, spec in p.items():
                if not isinstance(spec, dict):
                    continue
                key = norm(fname)
                # グローバルとリソース別の両方に同じ値を積む
                for store in (props, bucket):
                    d = store.setdefault(key, {"maxLength": set(), "enum": set(), "types": set()})
                    if isinstance(spec.get("maxLength"), int):
                        d["maxLength"].add(spec["maxLength"])
                    if isinstance(spec.get("enum"), list):
                        for v in spec["enum"]:
                            d["enum"].add(str(v))
                    if "type" in spec:
                        d["types"].add(str(spec["type"]))
                walk(spec, bucket)  # ネスト
        if isinstance(schema.get("items"), dict):
            walk(schema["items"], bucket)
        for k in ("allOf", "oneOf", "anyOf"):
            if isinstance(schema.get(k), list):
                for sub in schema[k]:
                    walk(sub, bucket)
    for f in glob.glob(os.path.join(api_dir, "*.yaml")) + glob.glob(os.path.join(api_dir, "*.yml")):
        stem = norm(os.path.splitext(os.path.basename(f))[0])
        bucket = by_resource.setdefault(stem, {})
        try:
            with open(f, encoding="utf-8", errors="replace") as fh:
                doc = yaml.safe_load(fh)
        except Exception:
            continue
        if isinstance(doc, dict):
            comps = doc.get("components", {})
            schemas = comps.get("schemas", {}) if isinstance(comps, dict) else {}
            if isinstance(schemas, dict):
                for s in schemas.values():
                    walk(s, bucket)
    return props, by_resource

api_props, api_by_resource = collect_api_props(api_dir)
if api_props is None:
    print("INFO: PyYAML 不在のため tables↔api 突合（db-contract）はスキップ（db-schema-completeness のみ実行）", file=sys.stderr)
else:
    def md_enum_values(raw):
        return set(re.findall(r"[A-Z][A-Z0-9_]{1,}", raw))
    for tname, cols in md_tables.items():
        # テーブル md と同名の API リソース（api/<tname>.yaml）があれば、それを優先突合スコープにする。
        # 無ければ従来どおりグローバル集約に fallback する（対応リソースを機械特定できないため）。
        resource_props = api_by_resource.get(tname)
        for cname, info in cols.items():
            if resource_props is not None and cname in resource_props:
                ap = resource_props[cname]; scoped = True
            elif cname in api_props:
                ap = api_props[cname]; scoped = False
            else:
                continue  # 同名フィールドが API に無ければ突合対象外（保守的）
            # 桁: VARCHAR(n) vs maxLength
            #   スコープ内の maxLength 集合の「いずれか」に一致すれば OK（一致するものが皆無のときだけ BLOCK）。
            #   従来の「1 つでも異なれば BLOCK」は、同名フィールドが別リソースで別桁を持つ場合に
            #   正当な設計を誤検知していた（cross-resource false positive）。by_resource 優先＋
            #   集合メンバシップ判定でこれを排除する。
            if info["length"] is not None and ap["maxLength"]:
                if info["length"] not in ap["maxLength"]:
                    exp = "・".join(str(x) for x in sorted(ap["maxLength"]))
                    scope_note = tname if scoped else "全 API 横断"
                    findings.append(dict(
                        severity="BLOCK", path=os.path.join(tables_dir, tname + ".md"), line=1,
                        category="db-contract",
                        message=f"「カラム {cname} の桁不一致: tables=VARCHAR({info['length']}) / api maxLength={exp}（照合スコープ: {scope_note}）」",
                        suggested_fix="tables の桁と api の maxLength を一致させる"))
            # enum: tables 型欄に enum 列挙がある場合のみ突合
            #   スコープ確定時（同名リソース）は厳密一致、グローバル fallback 時は部分集合で保守判定
            #   （プールされた別リソースの enum との等値比較による対称的な誤検知を避ける）。
            mev = md_enum_values(info["type"]) if re.search(r"enum", info["type"], re.IGNORECASE) else set()
            if mev and ap["enum"]:
                mismatch = (mev != ap["enum"]) if scoped else (not mev.issubset(ap["enum"]))
                if mismatch:
                    findings.append(dict(
                        severity="BLOCK", path=os.path.join(tables_dir, tname + ".md"), line=1,
                        category="db-contract",
                        message=f"「カラム {cname} の enum 値域不一致: tables={sorted(mev)} / api={sorted(ap['enum'])}」",
                        suggested_fix="enum 値域を コード値定義.md → _common.yaml → tables で一致させる"))

# ----------------------------------------------------------------------------
# (3) db-sequence-consistency : sequences/*.md の SQL ↔ tables/*.md 整合
#   (3a) INSERT INTO t(...) / UPDATE t SET col=... の参照列が当該テーブルに存在するか
#        （純カラムリスト型 INSERT＝スキーマ宣言は BLOCK、key=value/UPDATE の略記は SUGGEST）
#   (3b) col = ... INTERVAL 'N unit' の N・unit を、当該列の設計値（説明文の数値）と比較
#        （同単位で値違いなら BLOCK＝contract 矛盾。例: expires_at 30 days vs 「3 日」）
#   いずれも md_tables（上の parse_table_md 結果）を再利用する。
# ----------------------------------------------------------------------------
seq_dir = os.path.join(design, "sequences")
if os.path.isdir(seq_dir):
    IDENT = re.compile(r"^[a-z_][a-z0-9_]*$")
    _PERIOD_UNITS = [
        ("day",  ["日間", "日", "days", "day"]),
        ("min",  ["分間", "分", "minutes", "minute", "min"]),
        ("hour", ["時間", "hours", "hour"]),
        ("week", ["週間", "週", "weeks", "week"]),
        ("month",["ヶ月", "カ月", "months", "month"]),
        ("year", ["年間", "年", "years", "year"]),
    ]
    _SYN2C = {}; _ALLS = []
    for _c, _ss in _PERIOD_UNITS:
        for _x in _ss:
            _SYN2C[_x] = _c; _ALLS.append(_x)
    _ALLS.sort(key=len, reverse=True)
    PERIOD_RE   = re.compile(r"(\d+)\s*(" + "|".join(re.escape(x) for x in _ALLS) + r")")
    INTERVAL_RE = re.compile(r"INTERVAL\s+'(\d+)\s*([a-z]+)'", re.IGNORECASE)
    INSERT_HEAD = re.compile(r"INSERT\s+INTO\s+([a-z_][a-z0-9_]*)\s*\(", re.IGNORECASE)
    UPDATE_RE   = re.compile(r"UPDATE\s+([a-z_][a-z0-9_]*)\s+SET\s+(.+?)(?:\s+WHERE\b|$)", re.IGNORECASE)

    def _period_pairs(t):
        return {(int(m.group(1)), _SYN2C[m.group(2)]) for m in PERIOD_RE.finditer(t)}
    def _normalize(line):
        line = re.sub(r"<br\s*/?>", " ", line)
        line = line.replace("（", "(").replace("）", ")").replace("，", ",")
        return re.sub(r"\s+", " ", line)
    def _find_inserts(line):
        # NOW() 等の入れ子括弧に対応して INSERT INTO t(...) の (table, inner) を返す
        out = []
        for m in INSERT_HEAD.finditer(line):
            tbl = m.group(1); start = m.end(); depth = 1; j = start
            while j < len(line) and depth > 0:
                if line[j] == "(":
                    depth += 1
                elif line[j] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            out.append((tbl, line[start:j]))
        return out
    def _items(inner):
        out = []
        for it in inner.split(","):
            it = it.strip()
            if not it:
                continue
            if "=" in it:
                k, v = it.split("=", 1); out.append((k.strip(), v.strip()))
            else:
                out.append((it.strip(), ""))
        return out
    def _check_col(tbl, col, path, lineno, style):
        cols = md_tables.get(tbl)
        if cols is None:
            return  # 未知テーブル（別名/JOIN 等）は対象外＝誤検知防止
        if col in cols:
            return
        sev = "BLOCK" if style == "insert-list" else "SUGGEST"
        findings.append(dict(
            severity=sev, path=path, line=lineno, category="db-sequence-consistency",
            message=f"シーケンスの SQL がカラム「{tbl}.{col}」を参照していますが、tables/{tbl}.md のカラム定義に存在しません（{style}）。",
            suggested_fix=f"列名を tables/{tbl}.md の物理カラム名に合わせるか、不足カラムをテーブル定義へ追加する。"))
    def _check_interval(tbl, col, expr, path, lineno):
        cols = md_tables.get(tbl)
        if not cols or col not in cols:
            return
        m = INTERVAL_RE.search(expr)
        if not m:
            return
        unit = _SYN2C.get(m.group(2).lower())
        if not unit:
            return
        val = int(m.group(1))
        same = {v for (v, u) in _period_pairs(cols[col]["raw"]) if u == unit}
        if same and val not in same:
            exp = "・".join(str(v) for v in sorted(same))
            findings.append(dict(
                severity="BLOCK", path=path, line=lineno, category="db-sequence-consistency",
                message=f"シーケンスの SQL で {tbl}.{col} を「INTERVAL '{val} {m.group(2)}'」に設定していますが、tables/{tbl}.md の {col} 設計値（{unit}={exp}）と矛盾しています。",
                suggested_fix=f"INTERVAL 値を tables/{tbl}.md の {col}（{unit}={exp}）に合わせる。"))

    for sp in sorted(glob.glob(os.path.join(seq_dir, "*.md"))):
        with open(sp, encoding="utf-8", errors="replace") as fh:
            for lineno, raw in enumerate(fh, 1):
                line = _normalize(raw)
                for tbl, inner in _find_inserts(line):
                    tbl = norm(tbl)
                    if tbl not in md_tables:
                        continue
                    items = _items(inner)
                    style = "insert-list" if all(e == "" for _, e in items) else "insert-kv"
                    for col, expr in items:
                        col = norm(col)
                        if not IDENT.match(col):
                            continue
                        _check_col(tbl, col, sp, lineno, style)
                        if expr:
                            _check_interval(tbl, col, expr, sp, lineno)
                for m in UPDATE_RE.finditer(line):
                    tbl = norm(m.group(1))
                    if tbl not in md_tables:
                        continue
                    for col, expr in _items(m.group(2)):
                        col = norm(col)
                        if not IDENT.match(col):
                            continue
                        _check_col(tbl, col, sp, lineno, "update-set")
                        if expr:
                            _check_interval(tbl, col, expr, sp, lineno)

# ----------------------------------------------------------------------------
# 出力
# ----------------------------------------------------------------------------
if findings:
    print(json.dumps(findings, ensure_ascii=False, indent=2))
    sys.exit(1)

print(f"OK: tables/*.md の完全性・tables↔api 整合・sequences↔tables 整合に問題はありません（テーブル数: {len(md_tables)}）。")
PY
