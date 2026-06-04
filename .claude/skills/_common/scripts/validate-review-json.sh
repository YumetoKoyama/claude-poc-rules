#!/usr/bin/env bash
# _common/scripts/validate-review-json.sh
#
# review skill が書き出した review JSON が妥当な JSON か検証する。
# - パース成功: exit 0、stdout に "OK" を 1 行
# - パース失敗: exit 1、stderr にエラー位置と前後コンテキストを出力
#
# Usage:
#   validate-review-json.sh <path-to-review.json>
#
# review skill は本スクリプトを Write 直後に呼び、失敗時は自己修正して
# 再 Write → 再検証する。3 回失敗したら標準出力に
# "ERROR: invalid JSON after 3 attempts" を出して停止すること。

set -euo pipefail

JSON_PATH="${1:-}"

if [[ -z "$JSON_PATH" ]]; then
  echo "ERROR: review JSON のパスが指定されていません" >&2
  exit 2
fi

if [[ ! -f "$JSON_PATH" ]]; then
  echo "ERROR: ファイルが存在しません: $JSON_PATH" >&2
  exit 2
fi

# パース試行。失敗時はエラー位置と前後 200 文字を stderr に出す。
python3 - "$JSON_PATH" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

try:
    json.loads(content)
except json.JSONDecodeError as e:
    char_offset = e.pos
    # 前後 200 文字
    start = max(0, char_offset - 200)
    end = min(len(content), char_offset + 200)
    context = content[start:end]
    print(f"ERROR: invalid JSON at line {e.lineno} col {e.colno} (char {e.pos})", file=sys.stderr)
    print(f"  reason: {e.msg}", file=sys.stderr)
    print(f"  context (±200 chars around char {e.pos}):", file=sys.stderr)
    print("  ----", file=sys.stderr)
    print(f"  {context!r}", file=sys.stderr)
    print("  ----", file=sys.stderr)
    print("  hint: ASCII の \" \\ や生の改行が文字列内で未エスケープになっていないか確認", file=sys.stderr)
    sys.exit(1)

print("OK")
PY
