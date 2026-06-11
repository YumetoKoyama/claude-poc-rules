#!/usr/bin/env bash
# _common/scripts/check-stack-decided.sh
#
# 第1層（決定論）: 技術スタック確定表（*-00-stack.md）に「要確定」が
# 残っていないかを機械的に検査する、設計着手前ハードゲート。
#
# 検査内容:
#   - 確定表ファイルが存在しない → NG（「未記載 = 要確定」とみなし素通りさせない）
#   - 表の「状態」列に `要確定` が残る → NG（該当行を一覧表示）
#
# Usage:
#   check-stack-decided.sh [<repo-root>]
#     <repo-root>: 検査の起点。省略時はカレントディレクトリ。
#       - 親アンブレラから実行: claude-poc-frontend / claude-poc-backend 両方の確定表を検査
#       - 子リポジトリから実行: 自身の .claude/rules/*-00-stack.md を検査
#
# Exit:
#   0: すべて確定済み（設計着手可）
#   1: 要確定が残存、または確定表が存在しない（設計着手不可。人間に確定を依頼する）
#   2: 引数エラー

set -euo pipefail

ROOT="${1:-.}"

if [[ ! -d "$ROOT" ]]; then
  echo "ERROR: ディレクトリが存在しません: $ROOT" >&2
  exit 2
fi

# 検査対象の確定表を解決する
targets=()
missing=()

if compgen -G "$ROOT/.claude/rules/"*-00-stack.md > /dev/null 2>&1; then
  # 子リポジトリ単体（CI 等）
  while IFS= read -r f; do targets+=("$f"); done \
    < <(ls "$ROOT/.claude/rules/"*-00-stack.md)
else
  # 親アンブレラ
  for child in claude-poc-frontend claude-poc-backend; do
    expected="$ROOT/$child/.claude/rules"
    found=0
    if compgen -G "$expected/"*-00-stack.md > /dev/null 2>&1; then
      while IFS= read -r f; do targets+=("$f"); done < <(ls "$expected/"*-00-stack.md)
      found=1
    fi
    [[ $found -eq 0 ]] && missing+=("$expected/*-00-stack.md")
  done
fi

if [[ ${#targets[@]} -eq 0 && ${#missing[@]} -eq 0 ]]; then
  echo "NG: 技術スタック確定表（*-00-stack.md）が見つかりません（起点: $ROOT）"
  echo "    未記載は『要確定』とみなします。確定表を作成し、人間が確定値を記入してください。"
  exit 1
fi

ng=0

for m in "${missing[@]:-}"; do
  [[ -z "$m" ]] && continue
  echo "NG: 確定表が存在しません: $m（未記載 = 要確定）"
  ng=1
done

for f in "${targets[@]:-}"; do
  [[ -z "$f" ]] && continue
  # 「## 確定表」セクション内の、表の「状態」セルとしての `| 要確定 |` のみを検出する
  # （凡例セクションや本文の説明文には反応しない）
  hits="$(awk '/^## /{insec = ($0 ~ /^## 確定表/)} insec {printf "%d:%s\n", NR, $0}' "$f" \
    | grep -E '\|[[:space:]]*要確定[[:space:]]*\|' || true)"
  if [[ -n "$hits" ]]; then
    ng=1
    count="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
    echo "NG: 要確定が ${count} 件残っています: $f"
    # 行番号 + 項目名（表の 2 列目）を提示する
    printf '%s\n' "$hits" | while IFS= read -r line; do
      lineno="${line%%:*}"
      item="$(printf '%s' "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}')"
      echo "    - L${lineno}: ${item}"
    done
  else
    echo "OK: $f"
  fi
done

if [[ $ng -ne 0 ]]; then
  echo ""
  echo "設計フェーズ（design-from-requirements 以降)には進めません。"
  echo "上記の未確定項目を人間が確定し、確定表の「状態」を『確定』に更新してください。"
  echo "（Claude は既定値で自動補完してはならない / CLAUDE.md「技術スタックの正典と確定ルール」）"
  exit 1
fi

echo "すべての技術スタックが確定済みです。設計フェーズに進めます。"
exit 0
