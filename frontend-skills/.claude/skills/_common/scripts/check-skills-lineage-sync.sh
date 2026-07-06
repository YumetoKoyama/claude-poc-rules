#!/usr/bin/env bash
# _common/scripts/check-skills-lineage-sync.sh
#
# 【P-13 対応】スキル 3 系統（親 generic / frontend-skills / backend-skills）の
# ドリフト（意図しない分岐）を機械検知する。
#
# 背景: スキルが「親 .claude/skills/（generic 正典）」「frontend-skills/（FE 版）」
# 「backend-skills/（BE 版）」の 3 系統に分岐し、grafт（手動マージ）で維持されている。
# 既存 check-skills-sync.sh は「親 = 子」の完全一致検査のため 3 系統を扱えない。
#
# 方式（docs/process/08-skills-lineage-sync.md の方針を機械化）:
#   - _common/scripts/*.sh は「意図的分岐ファイル」を系統ルートの lineage-manifest.txt に
#     宣言する。宣言なしで親と内容が異なれば FAIL（ドリフト）。
#   - SKILL.md / references は grafт 前提のため内容比較しない。かわりに
#     (a) 親に存在して系統に無いスキルの一覧（情報）
#     (b) 系統にのみ存在するスキルの一覧（情報）
#     (c) grafт マーカー（<!-- rules 改善）の有無（由来追跡が消えていないか・WARN）
#     を報告する。
#
# lineage-manifest.txt の書式（系統ルート直下。# コメント可・1 行 1 相対パス）:
#   .claude/skills/_common/scripts/check-test-matrix.sh   # FE は IT 層なしのため固有版を維持
#
# Usage:
#   check-skills-lineage-sync.sh <parent-root> <lineage-root> [<lineage-root>...]
#   例: check-skills-lineage-sync.sh . frontend-skills backend-skills
#
# Exit: 0=ドリフトなし / 1=未宣言ドリフトあり / 2=引数エラー

set -euo pipefail

PARENT="${1:-}"
shift || true
if [[ -z "$PARENT" || $# -lt 1 ]]; then
  echo "Usage: check-skills-lineage-sync.sh <parent-root> <lineage-root>..." >&2
  exit 2
fi
if [[ ! -d "$PARENT/.claude/skills" ]]; then
  echo "ERROR: 親スキルが見つかりません: $PARENT/.claude/skills" >&2
  exit 2
fi

FAIL=0

sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

for LR in "$@"; do
  echo "=== 系統: $LR ==="
  if [[ ! -d "$LR/.claude/skills" ]]; then
    echo "  ERROR: 系統スキルが見つかりません: $LR/.claude/skills" >&2
    FAIL=1
    continue
  fi

  # manifest 読み込み
  declare -A ALLOW=()
  MF="$LR/lineage-manifest.txt"
  if [[ -f "$MF" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"
      line="$(echo "$line" | xargs || true)"
      [[ -n "$line" ]] && ALLOW["$line"]=1
    done < "$MF"
    echo "  manifest: $MF（意図的分岐 ${#ALLOW[@]} 件宣言）"
  else
    echo "  WARN: $MF が無い（意図的分岐が 0 件宣言。分岐があれば全て未宣言ドリフト扱い）"
  fi

  # (1) _common/scripts/*.sh のドリフト検査
  DRIFT=0
  while IFS= read -r ps; do
    rel=".claude/skills/_common/scripts/$(basename "$ps")"
    ls_="$LR/$rel"
    if [[ ! -f "$ls_" ]]; then
      # 系統のスキル本文がこのスクリプトを参照している場合のみ FAIL（設計フェーズ専用スクリプト等、
      # その系統で使わないものは info に留める）
      if grep -rq "$(basename "$ps")" "$LR/.claude/skills" --include='*.md' 2>/dev/null; then
        echo "  MISSING(script): $rel が系統に無いが系統スキルが参照している（配布漏れ・D-2 型）"
        FAIL=1; DRIFT=1
      else
        echo "  info(未配布・未参照): $rel（この系統のスキルは参照していないため配布不要と判断）"
      fi
      continue
    fi
    if [[ "$(sha "$ps")" != "$(sha "$ls_")" ]]; then
      if [[ -n "${ALLOW[$rel]:-}" ]]; then
        echo "  ok(declared-divergence): $rel（manifest 宣言済みの意図的分岐）"
      else
        echo "  DRIFT: $rel が親と異なるが manifest 未宣言（意図的なら $MF に追記、意図外なら同期する）"
        FAIL=1; DRIFT=1
      fi
    fi
  done < <(find "$PARENT/.claude/skills/_common/scripts" -maxdepth 1 -name '*.sh' | sort)

  # 系統にのみ存在するスクリプト（親への還流漏れ候補）
  while IFS= read -r ls_; do
    rel=".claude/skills/_common/scripts/$(basename "$ls_")"
    if [[ ! -f "$PARENT/$rel" ]]; then
      if [[ -n "${ALLOW[$rel]:-}" ]]; then
        echo "  ok(lineage-only, declared): $rel"
      else
        echo "  DRIFT(lineage-only): $rel は系統にのみ存在し manifest 未宣言（親正典への還流漏れの可能性。意図的なら manifest 宣言、generic 化できるなら親へ還流）"
        FAIL=1; DRIFT=1
      fi
    fi
  done < <(find "$LR/.claude/skills/_common/scripts" -maxdepth 1 -name '*.sh' 2>/dev/null | sort)

  [[ $DRIFT -eq 0 ]] && echo "  scripts: ドリフトなし"

  # (2) スキルの所在差分（情報提供。grafт 前提のため内容比較はしない）
  comm -23 \
    <(find "$PARENT/.claude/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort) \
    <(find "$LR/.claude/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort) \
    | sed 's/^/  info(親のみ): /' || true
  comm -13 \
    <(find "$PARENT/.claude/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort) \
    <(find "$LR/.claude/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort) \
    | sed 's/^/  info(系統のみ): /' || true

  # (3) grafт マーカーの残存確認（由来追跡が消えていないか）
  marked=$(grep -rl 'rules 改善' "$LR/.claude/skills" --include='SKILL.md' 2>/dev/null | wc -l || true)
  total=$(find "$LR/.claude/skills" -name 'SKILL.md' | wc -l)
  echo "  grafт マーカー付き SKILL.md: $marked / $total（0 なら由来追跡が失われている可能性・WARN）"

  unset ALLOW
  echo ""
done

if [[ $FAIL -ne 0 ]]; then
  echo "RESULT: FAIL — 未宣言ドリフトあり。意図的な分岐は各系統の lineage-manifest.txt に理由つきで宣言すること" >&2
  exit 1
fi
echo "RESULT: OK — 全系統ドリフトなし（宣言済み分岐のみ）"
