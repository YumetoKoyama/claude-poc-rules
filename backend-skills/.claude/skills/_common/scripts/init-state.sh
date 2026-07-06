#!/usr/bin/env bash
# _common/scripts/init-state.sh
#
# 第1層（決定論）: skills 横断の state JSON を初期化する。
# 既存の state があれば上書きせず、現状を出力するだけ（冪等）。
#
# Usage:
#   init-state.sh <phase> [extra_args] [max_iterations] [--reset]
#
# *** 反復回数の単一正典 ***
# max_iterations のデフォルト値（下記 MAX_ITER）が全 *-loop 工程共通の反復上限。
# 回数を変更する場合はここだけを編集する。loop スキル・CLAUDE.md・設計書には回数をハードコードしない。
#     <phase>          : requirements | design | implement | integration | overall
#     [extra_args]     : produce skill へ渡す追加引数（省略可）
#     [max_iterations] : 反復上限（省略時 3）
#     [--reset]        : 完了済み（passed/escalated）の state をアーカイブし
#                        stage=review, iteration=1 で再初期化する。
#                        未完了の state に対しては何もしない（冪等を維持）。
#
# 出力: state ファイルの絶対パスを stdout に 1 行で出す
#       （Claude 側でこのパスを Read して以降の判断に使う）

set -euo pipefail

# --reset フラグの検出（位置に関わらず）
RESET=false
POSITIONAL=()
for arg in "$@"; do
  if [[ "$arg" == "--reset" ]]; then
    RESET=true
  else
    POSITIONAL+=("$arg")
  fi
done

PHASE="${POSITIONAL[0]:-}"
EXTRA_ARGS="${POSITIONAL[1]:-}"
MAX_ITER="${POSITIONAL[2]:-3}"

if ! [[ "$MAX_ITER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: max_iterations は正の整数で指定してください: $MAX_ITER" >&2
  exit 1
fi

if [[ -z "$PHASE" ]]; then
  echo "ERROR: phase が指定されていません" >&2
  exit 1
fi
case "$PHASE" in
  requirements|design|implement|integration|overall) ;;
  *) echo "ERROR: 未知の phase: $PHASE（requirements|design|implement|integration|overall）" >&2; exit 1 ;;
esac

# .skills-state の出力/参照先を phase から決定論的に解決（CWD 非依存・所有リポ集約）
# shellcheck source=_state-root.sh
source "$(dirname "${BASH_SOURCE[0]}")/_state-root.sh"
: "${STATE_ROOT:=$(resolve_state_root "$PHASE")}"
STATE_DIR="${STATE_ROOT:-.}/.skills-state/${PHASE}"
STATE_FILE="${STATE_DIR}/state.json"
mkdir -p "$STATE_DIR"

# 破損 state の検出（D-08: 書き込み途中切断などで不正 JSON になった場合）
# → state-corrupt-<ts>.json としてアーカイブし、新規初期化に倒す（fail-stuck を防ぐ）。
#   続きから再開したい場合は rounds/ 配下の最新 review JSON とアーカイブから人手復元する。
if [[ -f "$STATE_FILE" ]]; then
  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$STATE_FILE" >/dev/null 2>&1; then
    CORRUPT_TS="$(date -u +%Y%m%dT%H%M%SZ)"
    mv "$STATE_FILE" "${STATE_DIR}/state-corrupt-${CORRUPT_TS}.json"
    echo "WARN: state.json が不正 JSON のためアーカイブしました: state-corrupt-${CORRUPT_TS}.json（新規初期化します。必要なら rounds/ の最新 review JSON から人手復元）" >&2
  fi
fi

# --reset: 完了済み state をアーカイブして再初期化する
if [[ "$RESET" == "true" && -f "$STATE_FILE" ]]; then
  # escalated が true の場合のみリセット（passed・中断状態はそのまま維持）
  IS_ESCALATED=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    s = json.load(f)
print('yes' if s.get('escalated') else 'no')
" "$STATE_FILE" 2>/dev/null || echo "no")

  if [[ "$IS_ESCALATED" == "yes" ]]; then
    # 旧 state をアーカイブ（タイムスタンプ付きリネーム）
    ARCHIVE_TS="$(date -u +%Y%m%dT%H%M%SZ)"
    mv "$STATE_FILE" "${STATE_DIR}/state-${ARCHIVE_TS}.json"
    echo "INFO: 完了済み state をアーカイブしました: state-${ARCHIVE_TS}.json（stage=review で再初期化します）" >&2
    RESET_ARCHIVED=true
    # fall through して新規 state を作成（stage=review で再開）
  else
    # 未完了 state に --reset → 冪等（そのまま返す）
    echo "INFO: state は未完了のため --reset をスキップしました（現在の state を維持）" >&2
    echo "$STATE_FILE"
    exit 0
  fi
fi

# 既存があれば更新せずパスのみ返す（冪等）
if [[ -f "$STATE_FILE" ]]; then
  echo "$STATE_FILE"
  exit 0
fi

# 既存がない場合のみ初期化
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
case "$PHASE" in
  requirements) ARTIFACT_PATH="docs/requirements/" ;;
  design)       ARTIFACT_PATH="docs/design/"       ;;
  implement)    ARTIFACT_PATH="."                  ;;  # implement は branch / PR 全体が対象
  integration)  ARTIFACT_PATH="docs/test/"         ;;  # integration-test-loop（結合テスト工程）
  overall)      ARTIFACT_PATH="."                  ;;  # review-implementation-overall（フィーチャ横断）
esac

# --reset 経由で実際にアーカイブした場合は stage=review から開始（produce はスキップ）
# RESET_ARCHIVED はアーカイブ実行時のみ true（上の --reset ブロック内で設定）
INIT_STAGE="produce"
# implement phase は TDD ファースト: 初期 stage を test-design とする
# （implement-loop の test-design → test-write → produce → [augment] → review → fix フローの起点）
if [[ "$PHASE" == "implement" ]]; then
  INIT_STAGE="test-design"
fi
if [[ "${RESET_ARCHIVED:-false}" == "true" ]]; then
  INIT_STAGE="review"
fi

# シェル変数は環境変数経由で渡し、非展開 heredoc(<<'PY') でコード破損/注入を防ぐ（H-3 改修）
ST_PHASE="$PHASE" ST_MAXITER="$MAX_ITER" ST_ARTIFACT="$ARTIFACT_PATH" \
ST_EXTRA="$EXTRA_ARGS" ST_NOW="$NOW" ST_FILE="$STATE_FILE" ST_STAGE="$INIT_STAGE" python3 - <<'PY'
import json, os, tempfile

def dump_atomic(obj, path):
  """D-08: 途中切断による不正 JSON を防ぐ（tmp へ書き fsync 後 rename）"""
  d = os.path.dirname(os.path.abspath(path)) or "."
  fd, tmp = tempfile.mkstemp(dir=d, prefix=".state-", suffix=".tmp")
  try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
      json.dump(obj, f, ensure_ascii=False, indent=2)
      f.flush()
      os.fsync(f.fileno())
    os.replace(tmp, path)
  except BaseException:
    try: os.unlink(tmp)
    except OSError: pass
    raise

state = {
  "phase":           os.environ["ST_PHASE"],
  "iteration":       1,
  "max_iterations":  int(os.environ["ST_MAXITER"]),
  "stage":           os.environ["ST_STAGE"],
  "artifact_path":   os.environ["ST_ARTIFACT"],
  "extra_args":      os.environ["ST_EXTRA"],
  "last_review_path": None,
  "review_counts":   {"block": 0, "suggest": 0, "nit": 0},
  "passed":          False,
  "escalated":       False,
  "created_at":      os.environ["ST_NOW"],
  "updated_at":      os.environ["ST_NOW"],
  "history": [
    {"iteration": 1, "stage": "init", "completed_at": os.environ["ST_NOW"]}
  ]
}
dump_atomic(state, os.environ["ST_FILE"])
PY

echo "$STATE_FILE"
