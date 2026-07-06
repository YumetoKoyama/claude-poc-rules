#!/usr/bin/env bash
# _common/scripts/_state-root.sh  （source 専用ヘルパ・実行はしない）
#
# 用途:
#   .skills-state の「出力先 / 参照先」ルートを phase から決定論的に解決する。
#   起動 CWD に依存せず、init/advance/record/... の各スクリプトが独立に同じ root を導けるため、
#   STATE_ROOT 環境変数を loop スキルから引き回す必要がなくなる（env 非依存）。
#
# 所有リポへの集約（「子に集める」）:
#   requirements / design … 所有リポ = claude-poc-docs（要件/設計成果物が置かれるリポ）
#   implement / integration … 実行中の子リポ（CWD の git toplevel = frontend/backend/batch）
#   overall                … 横断レビュー。親アンブレラ（CWD の git toplevel）
#
# 優先順位:
#   1. 明示 STATE_ROOT が設定されていればそれを尊重（人手上書き用）
#   2. requirements/design: 親アンブレラ直下なら claude-poc-docs を指す
#   3. 現在の git toplevel
#   4. "."（フォールバック）
resolve_state_root() {
  local phase="${1:-}"
  if [ -n "${STATE_ROOT:-}" ]; then
    printf '%s' "${STATE_ROOT%/}"
    return 0
  fi
  case "$phase" in
    requirements|design)
      # 親アンブレラから起動: 子 claude-poc-docs に集約する。
      # docs リポ単体チェックアウト(CI)や docs 内からの起動では下の git toplevel が docs を指す。
      # D-03: 既に state.json が存在する場所を最優先し、実行途中で解決先が変わる分裂を防ぐ。
      local _docs="" _top=""
      [ -e claude-poc-docs/.git ] && _docs="$(pwd)/claude-poc-docs"
      _top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      if [ -n "$_docs" ] && [ -f "$_docs/.skills-state/$phase/state.json" ]; then
        printf '%s' "$_docs"; return 0
      fi
      if [ -n "$_top" ] && [ -f "$_top/.skills-state/$phase/state.json" ]; then
        printf '%s' "$_top"; return 0
      fi
      if [ -n "$_docs" ]; then
        printf '%s' "$_docs"; return 0
      fi
      ;;
  esac
  local top
  if top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s' "$top"
    return 0
  fi
  printf '%s' "."
}
