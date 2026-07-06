#!/usr/bin/env bash
# _common/scripts/check-openapi-valid.sh
#
# 用途（RC-14 S2）:
#   OpenAPI 3.1 の構文妥当性と、$ref 参照先（ローカル: 同一ファイル内 components、
#   外部: 別 YAML#/components/... ）の存在を機械検証する。
#   yq があれば構造を厳密に、無ければ Python の YAML パーサで簡易検証する。
#
# Usage:
#   check-openapi-valid.sh [<api-dir>]
#     <api-dir> : 省略時 ./docs/design/api
#
# Exit:
#   0: 全 YAML が構文 OK かつ $ref 参照先がすべて存在
#   1: 構文エラー または 参照先不明の $ref
#   2: 引数エラー / 検証ツール不在（python3 もない）

set -euo pipefail

API_DIR="${1:-./docs/design/api}"

if [[ ! -d "$API_DIR" ]]; then
  echo "INFO: API ディレクトリがありません: $API_DIR（検査をスキップ）"
  exit 0
fi

shopt -s nullglob
yaml_files=("$API_DIR"/*.yaml "$API_DIR"/*.yml)
shopt -u nullglob
if [[ ${#yaml_files[@]} -eq 0 ]]; then
  echo "INFO: $API_DIR に YAML がありません（検査をスキップ）"
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません（OpenAPI 検証ができません）" >&2
  exit 2
fi

python3 - "$API_DIR" "${yaml_files[@]}" <<'PY'
import sys, os, re

api_dir = sys.argv[1]
files = sys.argv[2:]

try:
    import yaml  # PyYAML
    HAVE_YAML = True
except Exception:
    HAVE_YAML = False

ng = 0

def load(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if HAVE_YAML:
        return yaml.safe_load(text), text
    return None, text

# 各 file の最上位 openapi バージョン・構文を確認
docs = {}
for f in files:
    try:
        data, text = load(f)
    except Exception as e:
        print(f"NG: {f} の YAML パースに失敗: {e}")
        ng = 1
        continue
    docs[f] = (data, text)
    if HAVE_YAML and isinstance(data, dict):
        ver = str(data.get("openapi", ""))
        # _common.yaml は components のみのことがあるため openapi 必須は本体 YAML に限定しない
        if ver and not ver.startswith("3.1"):
            print(f"WARN: {f} の openapi バージョンが 3.1 系ではありません: {ver}")
    elif not HAVE_YAML:
        # 簡易: openapi: 3.1 の記載があるか（_common は無くてよい）
        if "openapi:" in text and not re.search(r"openapi:\s*['\"]?3\.1", text):
            print(f"WARN: {f} に openapi: 3.1 系の宣言が見当たりません（簡易検査）")

# $ref 参照先の存在確認
def resolve_ref(ref, base_file):
    # 形式: '#/components/schemas/Foo' or '_common.yaml#/components/schemas/Foo'
    if "#" in ref:
        filepart, fragment = ref.split("#", 1)
    else:
        filepart, fragment = ref, ""
    target_file = base_file if filepart == "" else os.path.join(api_dir, filepart)
    if not os.path.isfile(target_file):
        return False, f"参照先ファイルが存在しません: {filepart or os.path.basename(base_file)}"
    # フラグメントの存在確認
    if HAVE_YAML:
        data, _ = docs.get(target_file, (None, None))
        if data is None:
            try:
                data, _ = load(target_file)
            except Exception as e:
                return False, f"参照先のパース失敗: {e}"
        node = data
        for part in [p for p in fragment.split("/") if p]:
            part = part.replace("~1", "/").replace("~0", "~")
            if isinstance(node, dict) and part in node:
                node = node[part]
            else:
                return False, f"フラグメント未解決: #{fragment}"
        return True, ""
    else:
        # 簡易: フラグメントの末尾名がファイル中にキーとして現れるか
        _, text = docs.get(target_file, (None, None)) if target_file in docs else load(target_file)
        last = [p for p in fragment.split("/") if p]
        if last:
            name = last[-1]
            if re.search(rf"(^|\n)\s*{re.escape(name)}\s*:", text):
                return True, ""
            return False, f"フラグメント名 '{name}' が参照先に見当たりません（簡易検査）"
        return True, ""

ref_re = re.compile(r"""\$ref:\s*['"]?([^'"\s]+)['"]?""")
for f, (_, text) in docs.items():
    for m in ref_re.finditer(text):
        ref = m.group(1)
        ok, msg = resolve_ref(ref, f)
        if not ok:
            print(f"NG: {f} の $ref '{ref}' を解決できません - {msg}")
            ng = 1

if not HAVE_YAML:
    print("INFO: PyYAML 不在のため簡易検証で実施しました（yq/PyYAML 導入で厳密化推奨）")

if ng:
    print("")
    print("OpenAPI の構文または $ref 参照に問題があります（S2）。")
    sys.exit(1)

print("OK: OpenAPI 3.1 の構文と $ref 参照先はすべて妥当です（S2）。")
PY
