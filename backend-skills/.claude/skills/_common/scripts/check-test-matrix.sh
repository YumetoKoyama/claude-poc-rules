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
#       ※ 結合テストは検査しない（結合テストは別工程＝結合テスト工程）。
#   - integration（結合テスト工程）:
#       1. docs/test/結合テストマトリクス.md が存在し IT-XXX 行が 1 件以上
#          （結合点が無いフィーチャは「対象外」理由の明記で可）
#       2. RTM が存在する（Issue 番号が渡されれば当該行を突合）
#
# テスト「設計（ケース化）」のみを検査する。テスト「実施（実行）」は別。
# AC-XXX が無い共通基盤 Issue でも、設計書「実装内容」項目を観点化して
# TC-XXX を採番しマトリクスを必ず出すこと。
#
# Usage:
#   check-test-matrix.sh [<docs-test-dir>] [<issue-number>] [<phase>]
#     <docs-test-dir>: 省略時 ./docs/test
#     <issue-number> : 省略時は RTM の Issue 行突合をスキップ
#     <phase>        : unit | integration（省略時 unit）
#
# Exit:
#   0: 充足   1: 未作成・不備   2: 引数エラー

set -euo pipefail

TEST_DIR="${1:-./docs/test}"
ISSUE="${2:-}"
PHASE="${3:-unit}"

case "$PHASE" in
  unit|integration) ;;
  *) echo "ERROR: 未知の phase: $PHASE（unit|integration）" >&2; exit 2 ;;
esac

UT_MATRIX="$TEST_DIR/単体テストマトリクス.md"
IT_MATRIX="$TEST_DIR/結合テストマトリクス.md"
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

# RC-07: 「対象外」理由を所定の見出し/セル配下に限定して検出する。
# 本文のどこかに「なし」があるだけでは素通りさせない。
#   (a) 見出し行に対象外理由（例: 「## 対象外理由」「### 結合点なし（対象外）」）
#   (b) テーブルのセルとして対象外理由（| 区切りのセル内に「対象外」「該当なし」「N/A」）
it_exempt_reason_present() { # $1=file
  local f="$1"
  if grep -Eiq '^#{1,6}[[:space:]].*(対象外|該当なし|結合点(が)?なし|N/?A)' "$f"; then
    return 0
  fi
  if grep -E '^[[:space:]]*\|' "$f" | grep -Eiq '\|[[:space:]]*(対象外|該当なし|結合点(が)?なし|N/?A)[[:space:]]*\|'; then
    return 0
  fi
  return 1
}

if [[ "$PHASE" == "unit" ]]; then
  # 1. 単体テストマトリクス: 存在 + TC-XXX 行 1 件以上
  if [[ ! -f "$UT_MATRIX" ]]; then
    echo "NG: 単体テストマトリクスが存在しません: $UT_MATRIX"; ng=1
  else
    tc_count="$(count_pat 'TC-[0-9]{3}\b' "$UT_MATRIX")"
    if [[ "$tc_count" -lt 1 ]]; then
      echo "NG: 単体テストマトリクスに TC-XXX 行がありません: $UT_MATRIX"
      echo "    AC-XXX が無い基盤 Issue は設計書『実装内容』項目を観点化して TC を採番すること。"
      ng=1
    else
      echo "OK: $UT_MATRIX（TC ${tc_count} 件）"
    fi
    # RC-04 / T-03: TC-XXX の重複検出（複数 Issue 間の採番衝突）
    if [[ -f "$UT_MATRIX" ]]; then
      dup_tc="$(grep -Eo 'TC-[0-9]{3}\b' "$UT_MATRIX" | sort | uniq -d || true)"
      if [[ -n "$dup_tc" ]]; then
        echo "NG: 単体テストマトリクスに重複する TC-XXX があります:"
        printf '    %s\n' $dup_tc
        echo "    複数 Issue 間で TC 番号が衝突しています。既存マトリクスの最大番号からの続番で再採番してください。"
        ng=1
      fi
    fi
  fi
else
  # integration: 結合テストマトリクス: 存在 + IT-XXX 行（または対象外理由）
  if [[ ! -f "$IT_MATRIX" ]]; then
    echo "NG: 結合テストマトリクスが存在しません: $IT_MATRIX"; ng=1
  else
    it_count="$(count_pat 'IT-[0-9]{3}\b' "$IT_MATRIX")"
    if [[ "$it_count" -ge 1 ]]; then
      echo "OK: $IT_MATRIX（IT ${it_count} 件）"
    elif it_exempt_reason_present "$IT_MATRIX"; then
      echo "OK: $IT_MATRIX（IT 行なし・所定の対象外理由セクションを確認）"
    else
      echo "NG: 結合テストマトリクスに IT-XXX 行も対象外理由もありません: $IT_MATRIX"
      echo "    IT-XXX を採番するか、対象外（結合点なし 等）の理由を明記すること。"
      ng=1
    fi
  fi
fi

# RTM: 両フェーズ共通
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
    rtm_tc="$(count_pat '(TC|IT)-[0-9]{3}\b' "$RTM")"
    if [[ "$rtm_tc" -lt 1 ]]; then
      echo "NG: RTM にテスト ID（TC/IT-XXX）の参照がありません: $RTM"; ng=1
    else
      echo "OK: $RTM（テスト ID 参照 ${rtm_tc} 件）"
    fi
  fi
fi

if [[ $ng -ne 0 ]]; then
  echo ""
  echo "テスト設計（マトリクス）が未充足のため、次工程に進めません（phase=$PHASE）。"
  if [[ "$PHASE" == "unit" ]]; then
    echo "/test-design-from-issue を実行して docs/test/ に 単体マトリクス・RTM を出力してください。"
  else
    echo "/integration-test-from-design を実行して docs/test/ に 結合マトリクス・RTM を出力してください。"
  fi
  echo "（テスト実施そのものは別責務。ここで強制するのはテスト設計の成果物のみ）"
  exit 1
fi

echo ""
echo "テスト設計（phase=$PHASE）が揃っています。次工程に進めます。"
exit 0
