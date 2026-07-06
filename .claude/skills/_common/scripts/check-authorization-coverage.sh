#!/usr/bin/env bash
# _common/scripts/check-authorization-coverage.sh
#
# 用途（RC-14 S2 / RC-03）:
#   api/*.yaml の全 operationId と、セキュリティ設計.md / 認可設計.md に列挙された
#   operationId 行を突合し、認可設計に行が無い operationId（認可漏れ）を検出する。
#   public（認可不要）として明示されているものは許容する。
#
# Usage:
#   check-authorization-coverage.sh [<docs-design-dir>]
#     <docs-design-dir> : 省略時 ./docs/design（無ければ claude-poc-docs/... も探索）
#
# Exit:
#   0: 全 operationId が認可設計でカバー（または public 明示）
#   1: 認可設計に未掲載の operationId あり
#   2: 対象不在等

set -euo pipefail

DESIGN_DIR="${1:-}"
if [[ -z "$DESIGN_DIR" ]]; then
  for c in "./docs/design" "./claude-poc-docs/docs/design"; do
    [[ -d "$c" ]] && DESIGN_DIR="$c" && break
  done
fi
[[ -z "$DESIGN_DIR" ]] && DESIGN_DIR="./docs/design"

API_DIR="$DESIGN_DIR/api"
if [[ ! -d "$API_DIR" ]]; then
  echo "INFO: API ディレクトリがありません: $API_DIR（検査をスキップ）"
  exit 0
fi

authz_files=()
for f in "$DESIGN_DIR/認可設計.md" "$DESIGN_DIR/セキュリティ設計.md"; do
  [[ -f "$f" ]] && authz_files+=("$f")
done
if [[ ${#authz_files[@]} -eq 0 ]]; then
  echo "NG: 認可設計.md / セキュリティ設計.md が存在しません（認可設計が未作成）"
  echo "    全 operationId × 必要ロール × テナント条件 を認可設計に明記してください。"
  exit 1
fi

opids="$(grep -rhoE 'operationId:[[:space:]]*[A-Za-z0-9_]+' "$API_DIR" 2>/dev/null \
  | sed -E 's/operationId:[[:space:]]*//' | sort -u || true)"
if [[ -z "$opids" ]]; then
  echo "INFO: operationId を抽出できませんでした（検査をスキップ）"
  exit 0
fi

ng=0
total=0
missing=0
while IFS= read -r opid; do
  [[ -z "$opid" ]] && continue
  total=$((total+1))
  if grep -qhE "\b${opid}\b" "${authz_files[@]}" 2>/dev/null; then
    :
  else
    echo "NG: operationId 「$opid」が認可設計に未掲載（必要ロール×テナント条件、または public の明示が必要）"
    ng=1
    missing=$((missing+1))
  fi
done <<< "$opids"

echo "INFO: operationId 総数 $total / 認可設計 未掲載 $missing"
if [[ $ng -ne 0 ]]; then
  echo ""
  echo "認可設計に operationId の取りこぼしがあります（S2/RC-03）。"
  echo "public（認可不要）の場合も認可設計にその旨を明記してください。"
  exit 1
fi
echo "OK: 全 operationId が認可設計でカバーされています（S2/RC-03）。"
exit 0
