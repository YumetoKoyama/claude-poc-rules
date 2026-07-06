#!/usr/bin/env bash
# _common/scripts/check-claude-md-sync.sh
#
# 用途（RC-13）:
#   子 CLAUDE.md の「共有正典ブロック」が親 CLAUDE.md と一致するか、および
#   横断 AI ルール（cross-cutting.md）が各子 .claude/rules/ に配布されているかを検査する。
#   CI 到達性（親 CLAUDE.md 単独記載は CI 非到達）を機械的に担保する。
#
#   共有正典ブロックのマーカー:
#     <!-- shared-canon:start -->
#     ... 親が正典 ...
#     <!-- shared-canon:end -->
#
# Usage:
#   check-claude-md-sync.sh [<repo-root>]
#     <repo-root> : 親アンブレラのルート（省略時カレント）。
#                   子は claude-poc-frontend / claude-poc-backend / claude-poc-batch /
#                   claude-poc-docs / claude-poc-e2e を対象（存在するもののみ）。
#
# Exit:
#   0: 全子で共有正典ブロックが親と一致 かつ cross-cutting.md が配布済み
#   1: 不一致・未配布あり
#   2: 親 CLAUDE.md / マーカー不在等

set -euo pipefail

ROOT="${1:-.}"
PARENT_MD="$ROOT/CLAUDE.md"
PARENT_CC="$ROOT/rules/cross-cutting.md"

if [[ ! -f "$PARENT_MD" ]]; then
  echo "INFO: 親 CLAUDE.md がありません: $PARENT_MD（子リポ単体チェックアウトの可能性。検査をスキップ）"
  exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません" >&2; exit 2
fi

# 親の共有正典ブロックを抽出
extract_block() {
  python3 - "$1" <<'PY'
import sys, re
path = sys.argv[1]
try:
    t = open(path, encoding="utf-8").read()
except OSError:
    sys.exit(3)
m = re.search(r"<!--\s*shared-canon:start\s*-->(.*?)<!--\s*shared-canon:end\s*-->", t, re.DOTALL)
if not m:
    sys.exit(4)
sys.stdout.write(m.group(1).strip())
PY
}

parent_block="$(extract_block "$PARENT_MD")" || {
  rc=$?
  if [[ $rc -eq 4 ]]; then
    echo "NG: 親 CLAUDE.md に共有正典マーカー（<!-- shared-canon:start --> 〜 :end）がありません: $PARENT_MD"
    echo "    RC-13: CI 必須の最小規約を共有正典ブロックで定義し、各子へ配布してください。"
    exit 1
  fi
  echo "ERROR: 親 CLAUDE.md の読み取りに失敗" >&2; exit 2
}

ng=0
children=(claude-poc-frontend claude-poc-backend claude-poc-batch claude-poc-docs claude-poc-e2e)
found_any=0

for child in "${children[@]}"; do
  cdir="$ROOT/$child"
  [[ -d "$cdir" ]] || continue
  found_any=1
  child_md="$cdir/CLAUDE.md"
  if [[ ! -f "$child_md" ]]; then
    echo "NG: $child に CLAUDE.md がありません: $child_md"
    ng=1
  else
    child_block="$(extract_block "$child_md" 2>/dev/null || true)"
    if [[ -z "$child_block" ]]; then
      echo "NG: $child/CLAUDE.md に共有正典ブロックがありません（親から配布してください）"
      ng=1
    elif [[ "$child_block" != "$parent_block" ]]; then
      echo "NG: $child/CLAUDE.md の共有正典ブロックが親と一致しません（ドリフト）"
      ng=1
    else
      echo "OK: $child/CLAUDE.md 共有正典ブロック一致"
    fi
  fi
  # cross-cutting.md 配布確認（実装を伴う子に必須）
  case "$child" in
    claude-poc-frontend|claude-poc-backend|claude-poc-batch)
      child_cc="$cdir/.claude/rules/cross-cutting.md"
      if [[ ! -f "$child_cc" ]]; then
        echo "NG: $child に横断ルール cross-cutting.md が配布されていません: $child_cc"
        ng=1
      elif [[ -f "$PARENT_CC" ]] && ! diff -q "$PARENT_CC" "$child_cc" >/dev/null 2>&1; then
        echo "NG: $child/.claude/rules/cross-cutting.md が親 rules/cross-cutting.md と一致しません"
        ng=1
      else
        echo "OK: $child cross-cutting.md 配布済み"
      fi
      ;;
  esac
done

if [[ $found_any -eq 0 ]]; then
  echo "INFO: 子リポジトリが見つかりません（$ROOT 配下）。検査をスキップ"
  exit 0
fi

if [[ $ng -ne 0 ]]; then
  echo ""
  echo "子 CLAUDE.md の共有正典 / cross-cutting 配布に不整合があります（RC-13）。"
  echo "親から自動生成・同期配布し、CI 到達性を確保してください。"
  exit 1
fi
echo "OK: 共有正典ブロックと cross-cutting 配布は親と同期しています（RC-13）。"
exit 0
