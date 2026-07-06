#!/usr/bin/env bash
# .claude/hooks/protect-canon.sh
#
# 役割:
#   Claude Code の PreToolUse フック。正典（rules/ 配下と CLAUDE.md）を
#   Claude 実行中の編集から保護する。
#   - Edit / Write / MultiEdit / NotebookEdit のファイルパスを検査
#   - Bash の書き込み系コマンド（sed -i / tee / > / >> / cp / mv / install / truncate / dd）を検査
#
# エスケープハッチ:
#   環境変数 ALLOW_RULES_EDIT=1 を設定したセッションでは許可する
#   （人が明示的に Claude へルール編集を手伝わせたい場合）。
#   スキルの自動実行はフラグを立てないため常にブロックされる。
#
# 入出力:
#   stdin  : Claude Code が渡す PreToolUse の JSON
#   stdout : 通常は無出力で exit 0。ブロック時は permissionDecision=deny の JSON を出力。
#
# 注意:
#   - 依存は bash + python3。python3 が無い場合は fail-closed（deny）にする（D-10）。
#   - settings.json の deny は「常に絶対」でフラグ解除できないため、本フックで一元化している。
#
# 保護対象（D-07: 正典限定）:
#   - リポジトリルート直下の rules/ 配下（`^rules/`）
#   - 任意リポジトリの .claude/rules/ 配下（`/.claude/rules/`）
#   - リポジトリ境界直下の CLAUDE.md（ルート直下 / 子リポ直下）
#   ※ アプリ業務コードの中にある任意階層の `.../rules/`（例: src/domain/rules/、
#     packages/foo/rules/）は正典ではないため巻き込まない（旧 `(^|/)rules/` の過剰ブロック是正）。

set -u

# --- エスケープハッチ -------------------------------------------------------
if [ "${ALLOW_RULES_EDIT:-}" = "1" ]; then
  exit 0
fi

# --- D-10: python3 不在時は fail-closed（deny）-----------------------------
if ! command -v python3 >/dev/null 2>&1; then
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"protect-canon: python3 が見つからないため安全側で全操作をブロックしました（fail-closed）。python3 を導入するか、人手で操作してください。"}}
JSON
  exit 0
fi

INPUT=$(cat)

HOOK_INPUT="$INPUT" python3 - <<'PY'
import json, os, re, sys

raw = os.environ.get("HOOK_INPUT", "")
try:
    d = json.loads(raw)
except Exception:
    # 入力 JSON が壊れている場合は安全側でブロック（fail-closed）
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "protect-canon: PreToolUse 入力 JSON のパースに失敗したため安全側でブロックしました（fail-closed）。",
        }
    }))
    sys.exit(0)

tool = d.get("tool_name", "")
ti = d.get("tool_input", {}) or {}

def is_protected_path(p):
    """正典限定の保護判定（D-07）。
    - 任意リポの .claude/rules/ 配下
    - リポジトリ境界直下の rules/ 配下（パス先頭、または .git の隣＝リポルート直下相当）
    - リポジトリ境界直下の CLAUDE.md（先頭、または / 直後がルート扱い）
    任意階層の業務 .../rules/ は保護しない。
    """
    if not p:
        return False
    p = p.replace("\\", "/").lstrip("./")
    # 1) 子リポを含む .claude/rules/ は常に正典
    if re.search(r"(^|/)\.claude/rules/", p):
        return True
    # 2) ルート直下の rules/（パス先頭の rules/ のみ。中間階層の rules/ は除外）
    if re.match(r"^rules/", p):
        return True
    # 3) CLAUDE.md（パスの最終要素が CLAUDE.md で、かつルート/子リポ境界直下）
    #    - "CLAUDE.md"（先頭）
    #    - "<child-repo>/CLAUDE.md"（1 階層下＝子リポ直下）
    if re.match(r"^CLAUDE\.md$", p):
        return True
    if re.match(r"^[^/]+/CLAUDE\.md$", p):
        return True
    return False

def deny(target):
    reason = (
        "正典は Claude 実行中の編集を禁止しています（対象: %s）。"
        "rules/・.claude/rules/ 配下とリポジトリ直下の CLAUDE.md の変更は人手で行ってください。"
        "Claude に編集させる場合は ALLOW_RULES_EDIT=1 を設定したセッションで実行してください。"
        % target
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)

if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
    p = ti.get("file_path") or ti.get("notebook_path") or ""
    if is_protected_path(p):
        deny(p)

elif tool == "Bash":
    cmd = ti.get("command", "") or ""
    cmd = re.sub(r"\\\n", " ", cmd)  # 行継続を連結（C-2/H-4 改修）
    # 別インタプリタ経由の正典書込（best-effort）: python -c / perl -e / node -e 等
    if re.search(r"\b(python3?|perl|ruby|node)\b[^|;&]*-(c|e)\b[^|;&]*(\.claude/rules/|(^|[^\w./])rules/|CLAUDE\.md)", cmd):
        deny("bash(interpreter): " + cmd)
    # 書き込み系動詞（M-12: tee / tee -a を明示。sed -i / リダイレクト / cp / mv / install / truncate / dd）
    write_verb = r"(sed\s+-i|sed\s+--in-place|tee\b(\s+-a)?|>>|>|cp\s|mv\s|install\s|truncate|dd\s)"
    # 正典ターゲット（D-07: .claude/rules/・先頭 rules/・リポ直下 CLAUDE.md）
    # .claude/rules/ は任意リポで常に正典のため接頭辞（claude-poc-*/ 等のパス前置）を問わず捕捉する
    target = r"(\.claude/rules/|(^|[^\w./])rules/|(^|/)CLAUDE\.md)"
    if re.search(write_verb + r"[^|;&]*" + target, cmd):
        deny("bash: " + cmd)
    # リダイレクトで正典へ書き込むパターン（>/>> 先が正典）
    if re.search(r">>?\s*\"?([\w./-]*/)?(\.claude/rules/|rules/|CLAUDE\.md)", cmd):
        deny("bash: " + cmd)
    # tee の引数に正典パスが現れるパターン（パイプ経由 echo ... | tee rules/foo）
    if re.search(r"\btee\b(\s+-a)?\s+[^|;&]*(\.claude/rules/|(^|\s)rules/|([^/\s]+/)?CLAUDE\.md)", cmd):
        deny("bash: " + cmd)

sys.exit(0)
PY

exit 0
