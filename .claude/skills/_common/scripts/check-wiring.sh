#!/usr/bin/env bash
# _common/scripts/check-wiring.sh
#
# 第1層（決定論・再発防止ガード）: 「宣言と機構の分離」を機械検出する。
# すべての check-*.sh が、いずれかの SKILL.md から呼ばれている（配線済み）か、
# CI 専用 allowlist に明記されているかを検査する。orphan（0 参照かつ非 allowlist）は exit 1。
#
# 背景: 方針/機構を作っても「呼ぶ側に配線していない」と実際には効かない（SUGGEST escalate・
#       check-open-issues 等で発生）。本ガードでその欠陥クラスを再発防止する。
#
# Usage:  check-wiring.sh [<repo-root>]
# Exit:   0=全て配線済み or CI-allowlist / 1=orphan あり / 2=引数エラー

set -euo pipefail
ROOT="${1:-.}"
SCRIPTS_DIR="$ROOT/.claude/skills/_common/scripts"
SKILLS_DIR="$ROOT/.claude/skills"
[[ -d "$SCRIPTS_DIR" && -d "$SKILLS_DIR" ]] || { echo "ERROR: skills/scripts dir not found under $ROOT" >&2; exit 2; }

# CI ワークフロー（.github/workflows）で実行する前提のスクリプト（skill から呼ばれなくてよい）
CI_ALLOWLIST=("check-skills-sync.sh" "check-claude-md-sync.sh" "check-skill-names.sh" "check-wiring.sh")
is_ci_allowed(){ local n="$1"; for a in "${CI_ALLOWLIST[@]}"; do [[ "$a" == "$n" ]] && return 0; done; return 1; }

ng=0; orphans=()
for f in "$SCRIPTS_DIR"/*.sh; do
  bn="$(basename "$f")"
  if is_ci_allowed "$bn"; then
    # CI 専用は、少なくとも 1 つの workflow から呼ばれているか確認（無ければ警告）
    if ! grep -rqsF "$bn" "$ROOT/.github/workflows" 2>/dev/null; then
      echo "WARN: $bn は CI 専用 allowlist だが .github/workflows から参照されていません"
    else
      echo "OK(CI): $bn"
    fi
    continue
  fi
  # SKILL.md（_common 以外）からの参照数。
  # grep の no-match(exit 1) で set -e/pipefail に巻き込まれないよう一旦変数に受ける。
  matches="$(grep -rlF --include=SKILL.md -- "$bn" "$SKILLS_DIR" 2>/dev/null | grep -v '/_common/' || true)"
  if [[ -n "$matches" ]]; then refs="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"; else refs=0; fi
  if [[ "$refs" -ge 1 ]]; then
    echo "OK: $bn (refs=$refs)"
  else
    echo "NG: $bn は orphan（どの SKILL.md からも呼ばれていません）"
    orphans+=("$bn"); ng=1
  fi
done

if [[ $ng -ne 0 ]]; then
  echo
  echo "orphan スクリプト（宣言のみ・未配線）: ${orphans[*]}"
  echo "→ 呼び出す skill の手順に配線するか、CI 専用なら CI_ALLOWLIST と .github/workflows に追加すること。"
  exit 1
fi
echo "OK: 全 check スクリプトが配線済み（または CI 専用）"
