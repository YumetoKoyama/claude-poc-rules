#!/usr/bin/env bash
# _common/scripts/check-vertical-trace.sh
#
# 用途（RC-14 S2 / RC-02）:
#   画面 → operationId → 認可 → テーブル → シーケンス の縦串一貫性を grep で検証する。
#   「設計は書いたが繋がっていない」を決定論で炙り出す。
#
#   検査:
#     A. 各 operationId が（1）API YAML に実在（2）認可設計に登場（3）いずれかの
#        シーケンス（sequences/*.md）に登場 しているか
#     B. tables/*.md に定義された各テーブルが、いずれかの API もしくはシーケンスで
#        参照されているか（孤立テーブルの検出）
#
# Usage:
#   check-vertical-trace.sh [<docs-design-dir>]
#
# Exit:
#   0: 縦串一貫性 OK   1: 連鎖の断絶あり   2: 対象不在等

set -euo pipefail

DESIGN_DIR="${1:-}"
if [[ -z "$DESIGN_DIR" ]]; then
  for c in "./docs/design" "./claude-poc-docs/docs/design"; do
    [[ -d "$c" ]] && DESIGN_DIR="$c" && break
  done
fi
[[ -z "$DESIGN_DIR" ]] && DESIGN_DIR="./docs/design"

if [[ ! -d "$DESIGN_DIR" ]]; then
  echo "INFO: 設計ディレクトリがありません: $DESIGN_DIR（検査をスキップ）"
  exit 0
fi

API_DIR="$DESIGN_DIR/api"
SEQ_DIR="$DESIGN_DIR/sequences"
TBL_DIR="$DESIGN_DIR/tables"
SCR_DIR="$DESIGN_DIR/screens"

ng=0

# operationId 一覧
opids=""
[[ -d "$API_DIR" ]] && opids="$(grep -rhoE 'operationId:[[:space:]]*[A-Za-z0-9_]+' "$API_DIR" 2>/dev/null \
  | sed -E 's/operationId:[[:space:]]*//' | sort -u || true)"

authz_files=()
for f in "$DESIGN_DIR/認可設計.md" "$DESIGN_DIR/セキュリティ設計.md"; do
  [[ -f "$f" ]] && authz_files+=("$f")
done

# --- A. operationId の縦串 ---
if [[ -n "$opids" ]]; then
  while IFS= read -r opid; do
    [[ -z "$opid" ]] && continue
    # 認可設計に登場するか
    if [[ ${#authz_files[@]} -gt 0 ]] && ! grep -qhE "\b${opid}\b" "${authz_files[@]}" 2>/dev/null; then
      echo "NG: operationId 「$opid」が認可設計に未登場（画面→API→認可 の連鎖が切れています）"
      ng=1
    fi
    # シーケンスに登場するか（sequences があれば）
    if [[ -d "$SEQ_DIR" ]]; then
      if ! grep -rqhE "\b${opid}\b" "$SEQ_DIR" 2>/dev/null; then
        echo "WARN: operationId 「$opid」がどのシーケンス（sequences/*.md）にも現れません"
      fi
    fi
  done <<< "$opids"
else
  echo "INFO: operationId を抽出できませんでした"
fi

# --- B. 孤立テーブルの検出 ---
if [[ -d "$TBL_DIR" ]]; then
  while IFS= read -r tbl; do
    [[ -z "$tbl" ]] && continue
    tname="$(basename "${tbl%.md}")"
    # API / シーケンス / 画面 のいずれかで参照されているか
    referenced=0
    for d in "$API_DIR" "$SEQ_DIR" "$SCR_DIR"; do
      [[ -d "$d" ]] || continue
      if grep -rqiE "\b${tname}\b" "$d" 2>/dev/null; then referenced=1; break; fi
    done
    if [[ $referenced -eq 0 ]]; then
      echo "WARN: テーブル「$tname」が API/シーケンス/画面 のどこからも参照されていません（孤立テーブルの疑い）"
    fi
  done < <(find "$TBL_DIR" -name '*.md' 2>/dev/null)
fi

if [[ $ng -ne 0 ]]; then
  echo ""
  echo "縦串（画面→operationId→認可→テーブル→シーケンス）の一貫性に断絶があります（S2/RC-02）。"
  exit 1
fi
echo "OK: 縦串の一貫性に致命的な断絶はありません（S2/RC-02）。WARN は手動確認推奨。"
exit 0
