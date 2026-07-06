#!/usr/bin/env bash
# _common/scripts/check-skills-sync.sh
#
# 用途（RC-09）:
#   親 .claude/skills と各子 .claude/skills の一致を検査する（手コピーによるドリフト検出）。
#   差分（ファイル不在・内容相違）があれば NG。symlink/サブモジュール/CI 同期で
#   配布する前提のもと、CI で「ルート＝子の一致」を保証する。
#
# Usage:
#   check-skills-sync.sh [<repo-root>]
#     <repo-root> : 親アンブレラのルート（省略時カレント）。
#
# Exit:
#   0: 全子のスキルが親と一致（または子にスキルが無く配布対象外）
#   1: ドリフト検出
#   2: 親スキル不在等

set -euo pipefail

ROOT="${1:-.}"
PARENT_SKILLS="$ROOT/.claude/skills"

if [[ ! -d "$PARENT_SKILLS" ]]; then
  echo "INFO: 親 .claude/skills がありません: $PARENT_SKILLS（検査をスキップ）"
  exit 0
fi

children=(claude-poc-frontend claude-poc-backend claude-poc-batch claude-poc-docs claude-poc-e2e)
ng=0
found_any=0

for child in "${children[@]}"; do
  cskills="$ROOT/$child/.claude/skills"
  [[ -d "$ROOT/$child" ]] || continue
  found_any=1
  if [[ ! -d "$cskills" ]]; then
    # 子にスキルディレクトリが無い場合: symlink 運用ならリンク不在 = NG
    echo "NG: $child に .claude/skills がありません（親スキルが未配布）: $cskills"
    ng=1
    continue
  fi
  # symlink の場合: リンク先が親スキルの実体を指し、有効であることを検証する（M-2 改修）
  if [[ -L "$cskills" ]]; then
    rt="$(readlink -f "$cskills" 2>/dev/null || true)"
    pabs="$(readlink -f "$PARENT_SKILLS" 2>/dev/null || true)"
    if [[ -n "$rt" && -d "$rt" && "$rt" == "$pabs" ]]; then
      echo "OK: $child/.claude/skills は親を指す symlink（→ $(readlink "$cskills")）。配布 OK"
    else
      echo "NG: $child/.claude/skills は symlink ですがリンク先が親スキルでない/壊れています（→ $(readlink "$cskills")）"
      ng=1
    fi
    continue
  fi
  # 実体コピーの場合（H-1/H-6 改修）:
  #   本メソドロジは「各子が親スキルのサブセット＋子固有スキル」を持つ multi-repo 構成。
  #   よって NG にするのは「親・子の両方に存在し、内容が相違する共有スキル（＝ドリフト）」のみ。
  #     - 親のみ存在（子が持たない）       = 意図的サブセット → OK
  #     - 子のみ存在（例: create-issues-from-docs 等の子固有スキル） = OK（参考表示）
  #     - 両方に存在し内容相違             = ドリフト → NG（本検査の本来の目的）
  drift=""; childonly=0
  while IFS= read -r -d '' cf; do
    base="$(basename "$cf")"
    case "$base" in *.tmp|.writetest) continue;; esac
    case "$cf" in *".skills-state"*) continue;; esac
    rel="${cf#"$cskills"/}"
    pf="$PARENT_SKILLS/$rel"
    if [[ ! -e "$pf" ]]; then
      childonly=$((childonly+1))
    elif ! diff -q --strip-trailing-cr "$pf" "$cf" >/dev/null 2>&1; then
      drift+="    drift(内容相違): $rel"$'\n'
    fi
  done < <(find "$cskills" -type f -print0)
  if [[ -n "$drift" ]]; then
    echo "NG: $child/.claude/skills に親との内容ドリフトがあります（共有スキルが不一致）:"
    printf '%s' "$drift" | head -40
    ng=1
  else
    echo "OK: $child/.claude/skills は親と整合（共有スキルは全て一致／子固有スキル ${childonly} 件・サブセット配置を許容）"
  fi
done

if [[ $found_any -eq 0 ]]; then
  echo "INFO: 子リポジトリが見つかりません（検査をスキップ）"
  exit 0
fi

if [[ $ng -ne 0 ]]; then
  echo ""
  echo "スキル正典が子リポへ未同期です（RC-09）。symlink / サブモジュール / CI 同期で配布してください。"
  exit 1
fi
echo "OK: スキル正典が全子リポと一致しています（RC-09）。"
exit 0
