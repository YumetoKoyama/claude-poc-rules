#!/usr/bin/env bash
# _common/scripts/check-adopted.sh
#
# 第1層（決定論・採択ゲート / M-6）:
#   ローカル実行で後続フェーズ（design / implement 等）へ進む前に、入力成果物が
#   採択（= origin/main へマージ済み）であることを機械的に検査する。
#   従来は SKILL.md 本文の「git log で確認」指示＝AI の自己規律に依存していたため、
#   本スクリプトに外出しして決定論的に強制する。
#
# 検査内容（指定パスごと）:
#   1. 指定パスがベース ref（既定 origin/main）に存在する
#   2. 採択済みコミット(HEAD)がベース ref と差分なし（コミット間比較）
#   3. 未コミット変更・git stash 退避が当該パスに無い（採択ゲート回避の検出）
#
# Usage:
#   check-adopted.sh <path> [<path> ...] [--base <ref>] [--repo <dir>]
#     <path> : 採択確認したい成果物パス（例: docs/design / docs/requirements）
#     --base : 比較先 ref（既定: origin/main、無ければ main）
#     --repo : 当該成果物が存在する git 作業ツリーのディレクトリ。
#              省略時は各パスの先頭ディレクトリが独立した git 作業ツリー
#              （例: 別リポを checkout した claude-poc-docs/）なら自動でそこを採用する。
#              これにより「backend から実行したのに backend の origin/main を見て
#              docs の採択を誤判定する」穴（3.9）を塞ぐ。
#
# Exit:
#   0: 全パスが採択済み（マージ済み・差分なし・退避なし）→ 後続フェーズ可
#   1: 未採択（未マージ／差分あり／退避あり／ベースに不在／ベース ref 解決不可）→ 中断
#   2: git 不在等の環境エラー

set -euo pipefail

BASE=""
REPO=""
paths=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    *) paths+=("$1"); shift ;;
  esac
done

if [[ ${#paths[@]} -eq 0 ]]; then
  echo "ERROR: usage: check-adopted.sh <path> [<path> ...] [--base <ref>] [--repo <dir>]" >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git が見つかりません" >&2; exit 2
fi

# 3.9 対策(1): 成果物が存在するリポを特定する。
#   --repo 明示 > パス先頭ディレクトリが別 git 作業ツリー > カレント の順。
resolve_repo() {
  local p="$1"
  if [[ -n "$REPO" ]]; then echo "$REPO"; return; fi
  local top="${p%%/*}"
  if [[ "$top" != "$p" && -d "$top/.git" ]]; then echo "$top"; return; fi
  echo "."
}
relpath() { local repo="$1" p="$2"; if [[ "$repo" != "." ]]; then echo "${p#"$repo"/}"; else echo "$p"; fi; }
resolve_base() {
  local b="$1" r="$2"
  if [[ -z "$b" ]]; then
    if git -C "$r" rev-parse --verify -q origin/main >/dev/null; then b="origin/main"
    elif git -C "$r" rev-parse --verify -q main >/dev/null; then b="main"; fi
  fi
  echo "$b"
}

ng=0
for p in "${paths[@]}"; do
  repo="$(resolve_repo "$p")"
  rp="$(relpath "$repo" "$p")"
  if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "NG: $p のリポ($repo)が git 作業ツリーではありません"; ng=1; continue
  fi
  base="$(resolve_base "$BASE" "$repo")"
  if [[ -z "$base" ]] || ! git -C "$repo" rev-parse --verify -q "$base" >/dev/null; then
    echo "NG: $p: 採択の基準となるベース ref（origin/main 等）を $repo で解決できません。"
    echo "    'git -C $repo fetch origin' 後に再実行するか、--base <ref> を指定してください。"
    ng=1; continue
  fi
  # 1. ベースに存在するか
  #    注意: `git ls-tree ... | grep -q .` は pipefail 下で SIGPIPE により
  #    間欠的に誤検知（141 終了）するため、変数に受けてから空判定する。
  listing="$(git -C "$repo" ls-tree -r --name-only "$base" -- "$rp" 2>/dev/null || true)"
  if [[ -z "$listing" ]]; then
    echo "NG: $p はベース($base)に存在しません（未採択／未マージ）"
    ng=1; continue
  fi
  # 2. 採択済みコミット(HEAD)がベースと差分なしか（コミット間比較 → stash で作業ツリーを
  #    一時的に綺麗にしてすり抜ける手口に強い）
  #    --ignore-cr-at-eol: WSL/Windows 環境で CRLF↔LF の行末差分を誤検知しない
  if ! git -C "$repo" diff --quiet --ignore-cr-at-eol "$base" HEAD -- "$rp" 2>/dev/null; then
    echo "NG: $p の HEAD がベース($base)へ未マージです（採択前のコミットで後続に進めません）"
    ng=1; continue
  fi
  # 3a. 未コミット/インデックスの変更検出
  #    --ignore-cr-at-eol: WSL/Windows 環境で CRLF↔LF の行末差分を誤検知しない
  worktree_diff=$(git -C "$repo" diff --ignore-cr-at-eol HEAD -- "$rp" 2>/dev/null)
  index_diff=$(git -C "$repo" diff --cached --ignore-cr-at-eol HEAD -- "$rp" 2>/dev/null)
  if [[ -n "$worktree_diff" || -n "$index_diff" ]]; then
    echo "NG: $p に未コミットのローカル変更があります（採択済みの内容で進めてください）"
    ng=1; continue
  fi
  # 3b. 3.9 対策(2): stash に当該パスを含むエントリが退避されていないか（pop で未採択内容を使う手口）
  stash_hit=0
  while IFS= read -r st; do
    [[ -z "$st" ]] && continue
    if git -C "$repo" stash show --name-only "$st" 2>/dev/null | grep -Eqx -- "$rp|$rp/.*"; then
      stash_hit=1; break
    fi
  done < <(git -C "$repo" stash list --format='%gd' 2>/dev/null)
  if [[ $stash_hit -eq 1 ]]; then
    echo "NG: $p に関する変更が git stash に退避されています（採択ゲート回避の疑い）。stash を整理してから再実行してください。"
    ng=1; continue
  fi
  echo "OK: $p は採択済み（$repo: $base にマージ済み・差分/退避なし）"
done

if [[ $ng -ne 0 ]]; then
  echo ""
  echo "採択ゲート未通過（M-6）。入力成果物を人手レビュー→docs main へ PR マージ（採択）してから"
  echo "後続フェーズ（design-from-requirements / implement-from-issue 等）に進んでください。"
  exit 1
fi
echo "OK: 採択ゲート通過。後続フェーズに進めます。"
exit 0
