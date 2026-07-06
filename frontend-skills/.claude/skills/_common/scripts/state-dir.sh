#!/usr/bin/env bash
# _common/scripts/state-dir.sh
#
# 用途（D-03: state 分裂防止）:
#   phase の .skills-state ディレクトリの「絶対パス」を 1 行出力する。
#   SKILL.md 本文・LLM の Write は相対 `.skills-state/...` を直書きせず、
#   必ず本スクリプトの出力を使う（決定論スクリプトと同じ _state-root.sh で解決するため、
#   書き手によって置き場が分裂しない）。
#
# Usage: state-dir.sh <phase>       # 例: state-dir.sh design
# Exit : 0=成功 / 2=引数エラー
set -euo pipefail
phase="${1:-}"
[ -z "$phase" ] && { echo "Usage: state-dir.sh <phase>" >&2; exit 2; }
. "$(dirname "${BASH_SOURCE[0]}")/_state-root.sh"
printf '%s/.skills-state/%s\n' "$(resolve_state_root "$phase")" "$phase"
