#!/usr/bin/env bash
# _common/scripts/check-review-output.sh
#
# オーケストレーター（*-loop）が review skill 完了後に呼ぶ決定論チェック。
# review JSON が期待パスに存在し、スキーマ検証に通ることを機械的に保証する。
#
# review skill は Claude（LLM）が JSON を Write するため、生成されないケースがある。
# 本スクリプトはそれを検出し、オーケストレーターに fail を返す。
#
# Usage:
#   check-review-output.sh <phase>
#
# 動作:
#   1. state.json から現在の iteration を取得
#   2. .skills-state/<phase>/round-<N>-review.json の存在を確認
#   3. validate-review-json.sh でスキーマ検証
#   4. 成功: stdout にパスを出力、exit 0
#      失敗: stderr にエラー、exit 1
#
# オーケストレーターは review skill の stdout（JSON パス）ではなく、
# 本スクリプトの stdout を正典として使う。

set -euo pipefail

PHASE="${1:-}"
if [[ -z "$PHASE" ]]; then
  echo "Usage: check-review-output.sh <phase>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# iteration を取得
N=$(bash "$SCRIPT_DIR/get-review-iteration.sh" "$PHASE" 2>/dev/null) || {
  echo "ERROR: iteration の取得に失敗しました（phase=$PHASE）" >&2
  exit 1
}

# .skills-state の出力/参照先を phase から決定論的に解決（CWD 非依存・所有リポ集約）
# shellcheck source=_state-root.sh
source "$(dirname "${BASH_SOURCE[0]}")/_state-root.sh"
: "${STATE_ROOT:=$(resolve_state_root "$PHASE")}"
EXPECTED="${STATE_ROOT:-.}/.skills-state/${PHASE}/round-${N}-review.json"

# 存在チェック
if [[ ! -f "$EXPECTED" ]]; then
  echo "ERROR: review JSON が生成されていません: $EXPECTED" >&2
  echo "  review skill が JSON の Write を完了しなかった可能性があります。" >&2
  echo "  /review-${PHASE} を再実行してください。" >&2
  exit 1
fi

# スキーマ検証
VALIDATE_OUT=$(bash "$SCRIPT_DIR/validate-review-json.sh" "$EXPECTED" 2>&1)
VALIDATE_RC=$?
if [[ $VALIDATE_RC -ne 0 ]]; then
  echo "$VALIDATE_OUT" >&2
  echo "ERROR: review JSON のスキーマ検証に失敗しました: $EXPECTED" >&2
  exit 1
fi

# 成功: パスを stdout に出力
echo "$EXPECTED"
