#!/usr/bin/env bash
# _common/scripts/check-test-matrix.sh
#
# 第1層（決定論）: テスト設計成果物（マトリクス・RTM）が own リポジトリの
# docs/test/ に出力されているかを機械的に検査するハードゲート。
# 設計思想は check-stack-decided.sh（設計着手前ゲート）と同じ。
#
# フェーズで検査対象を切り替える:
#   - unit（製造フェーズ・既定）:
#       1. docs/test/単体テストマトリクス.md が存在し TC-XXX 行が 1 件以上
#       2. docs/test/トレーサビリティマトリクス.md（RTM）が存在し、
#          （Issue 番号が渡された場合）当該 Issue(#N) の行がある
#       ※ フロントエンドに IT 層はないため integration フェーズは使用しない。
#
# テスト「設計（ケース化）」のみを検査する。テスト「実施（実行）」は別。
# AC-XXX が無い共通基盤 Issue でも、設計書「実装内容」項目を観点化して
# TC-XXX を採番しマトリクスを必ず出すこと。
#
# Usage:
#   check-test-matrix.sh [<docs-test-dir>] [<issue-number>] [<phase>]
#     <docs-test-dir>: 省略時 ./docs/test
#     <issue-number> : 省略時は RTM の Issue 行突合をスキップ
#     <phase>        : unit（省略時 unit）
#
# Exit:
#   0: 充足   1: 未作成・不備   2: 引数エラー

set -euo pipefail

TEST_DIR="${1:-./docs/test}"
ISSUE="${2:-}"
PHASE="${3:-unit}"

case "$PHASE" in
  unit) ;;
  *) echo "ERROR: フロントエンドでは unit フェーズのみ対応しています: $PHASE" >&2; exit 2 ;;
esac

UT_MATRIX="$TEST_DIR/単体テストマトリクス.md"
RTM="$TEST_DIR/トレーサビリティマトリクス.md"

if [[ ! -d "$TEST_DIR" ]]; then
  echo "NG: docs/test ディレクトリが存在しません: $TEST_DIR"
  echo "    テスト設計（マトリクス）が未作成です。"
  exit 1
fi

ng=0

count_pat() { # $1=pattern $2=file
  { grep -Eo "$1" "$2" || true; } | sort -u | wc -l | tr -d ' '
}

# 単体テストマトリクス: 存在 + TC-XXX 行 1 件以上
if [[ ! -f "$UT_MATRIX" ]]; then
  echo "NG: 単体テストマトリクスが存在しません: $UT_MATRIX"; ng=1
else
  tc_count="$(count_pat 'TC-[0-9]{3}' "$UT_MATRIX")"
  if [[ "$tc_count" -lt 1 ]]; then
    echo "NG: 単体テストマトリクスに TC-XXX 行がありません: $UT_MATRIX"
    echo "    AC-XXX が無い基盤 Issue は設計書『実装内容』項目を観点化して TC を採番すること。"
    ng=1
  else
    echo "OK: $UT_MATRIX（TC ${tc_count} 件）"
  fi
fi

# RTM
if [[ ! -f "$RTM" ]]; then
  echo "NG: トレーサビリティマトリクス（RTM）が存在しません: $RTM"; ng=1
else
  if [[ -n "$ISSUE" ]]; then
    if grep -Eq "#${ISSUE}([^0-9]|$)" "$RTM"; then
      echo "OK: $RTM（Issue #${ISSUE} の行を確認）"
    else
      echo "NG: RTM に Issue #${ISSUE} の行がありません: $RTM"
      echo "    今回の Issue / AC（または実装内容項目）/ テスト ID を RTM に反映すること。"
      ng=1
    fi
  else
    rtm_tc="$(count_pat 'TC-[0-9]{3}' "$RTM")"
    if [[ "$rtm_tc" -lt 1 ]]; then
      echo "NG: RTM に TC-XXX の参照がありません: $RTM"; ng=1
    else
      echo "OK: $RTM（TC 参照 ${rtm_tc} 件）"
    fi
  fi
fi

if [[ $ng -ne 0 ]]; then
  echo ""
  echo "テスト設計（マトリクス）が未充足のため、次工程に進めません（phase=$PHASE）。"
  echo "/test-design-from-issue を実行して docs/test/ に 単体マトリクス・RTM を出力してください。"
  echo "（テスト実施そのものは別責務。ここで強制するのはテスト設計の成果物のみ）"
  exit 1
fi

echo ""
echo "テスト設計（phase=$PHASE）が揃っています。次工程に進めます。"
exit 0
