#!/usr/bin/env bash
# _common/scripts/validate-yaml-format.sh
#
# 第1層（決定論）: 指定ディレクトリ配下の YAML ファイルに対して
# Prettier のフォーマットチェックを実行し、review JSON と同じ
# findings 形式で stdout に JSON 配列を出力する。
#
# 検出内容:
#   - BLOCK  / openapi: Prettier が YAML をパースできない（構文エラー・インデント異常）
#   - NIT    / style  : YAML の内容は正しいがフォーマット規約に違反している
#
# Usage:
#   validate-yaml-format.sh <yaml-dir>
#     <yaml-dir> : YAML ファイルを含むディレクトリ（例: docs/design/api）
#
# 出力: findings JSON 配列を stdout に。
#
# 依存:
#   - npx（Node.js 環境で自動的に prettier を解決する）
#   - python3（findings JSON の組み立てに使用）
#
# Exit:
#   0: 正常（findings の有無に関わらず）
#   2: 引数エラー

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "ERROR: yaml-dir を指定してください" >&2
  echo "Usage: validate-yaml-format.sh <yaml-dir>" >&2
  exit 2
fi

YAML_DIR="$1"

# npx がなければ空の findings を返してフェイルオープン
if ! command -v npx &>/dev/null; then
  echo "[]"
  exit 0
fi

# ファイルリストを収集
mapfile -t yaml_files < <(find "$YAML_DIR" -maxdepth 1 \( -name "*.yaml" -o -name "*.yml" \) -type f 2>/dev/null | sort)

if [[ ${#yaml_files[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

# 各ファイルを個別チェックして "path\tstatus" を temp ファイルに書き出す
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

for yaml in "${yaml_files[@]}"; do
  output=$(npx --yes prettier@3 --check "$yaml" 2>&1) && {
    # フォーマット正常
    echo "${yaml}"$'\t'"ok" >> "$TMPFILE"
  } || {
    if echo "$output" | grep -qiE \
      "(SyntaxError|ParseError|parse error|bad indentation|YAMLException|unknown tag|duplicate key|unexpected|cannot read)"; then
      echo "${yaml}"$'\t'"parse_error" >> "$TMPFILE"
    else
      echo "${yaml}"$'\t'"format_error" >> "$TMPFILE"
    fi
  }
done

# python3 に temp ファイルを渡して findings JSON を構築（UTF-8 強制で文字化け防止）
PYTHONUTF8=1 python3 - "$TMPFILE" <<'PY'
import json, sys

results = {}
with open(sys.argv[1]) as fp:
    for line in fp:
        line = line.rstrip("\n")
        if "\t" not in line:
            continue
        path, status = line.split("\t", 1)
        results[path] = status

findings = []
for path, status in sorted(results.items()):
    if status == "parse_error":
        findings.append({
            "severity": "BLOCK",
            "path": path,
            "line": None,
            "category": "openapi",
            "message": "YAML 構文エラー: Prettier がパースできません。インデント異常または構文エラーがあります。",
            "suggested_fix": "YAML のインデントと構文を修正してください。openapi-typescript での型生成も失敗します。",
        })
    elif status == "format_error":
        findings.append({
            "severity": "NIT",
            "path": path,
            "line": None,
            "category": "style",
            "message": "YAML フォーマット違反: Prettier の規約に従っていません（インデント幅・クォート・末尾スペース等）。",
            "suggested_fix": "npx prettier --write " + path + " を実行してフォーマットを自動修正してください。",
        })

order = {"BLOCK": 0, "SUGGEST": 1, "NIT": 2}
findings.sort(key=lambda x: (order.get(x["severity"], 99), x["path"]))
json.dump(findings, sys.stdout, ensure_ascii=False, indent=2)
sys.stdout.write("\n")
PY
