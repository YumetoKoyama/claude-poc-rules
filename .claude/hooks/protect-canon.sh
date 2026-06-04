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
#   - 依存は bash + python3。python3 が無い場合はフェイルオープン（block-secrets.sh と同方針）。
#   - settings.json の deny は「常に絶対」でフラグ解除できないため、本フックで一元化している。

set -u

# --- エスケープハッチ -------------------------------------------------------
if [ "${ALLOW_RULES_EDIT:-}" = "1" ]; then
  exit 0
fi

INPUT=$(cat)

HOOK_INPUT="$INPUT" python3 - <<'PY'
import json, os, re, sys

raw = os.environ.get("HOOK_INPUT", "")
try:
    d = json.loads(raw)
except Exception:
    sys.exit(0)

tool = d.get("tool_name", "")
ti = d.get("tool_input", {}) or {}

def is_protected_path(p):
    if not p:
        return False
    p = p.replace("\\", "/")
    if re.search(r"(^|/)rules/", p):
        return True
    if re.search(r"(^|/)CLAUDE\.md$", p):
        return True
    return False

def deny(target):
    reason = (
        "正典は Claude 実行中の編集を禁止しています（対象: %s）。"
        "rules/ 配下と CLAUDE.md の変更は人手で行ってください。"
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
    write_verb = r"(sed\s+-i|sed\s+--in-place|tee|>>|>|cp\s|mv\s|install\s|truncate|dd\s)"
    target = r"(^|[^\w])(rules/|CLAUDE\.md)"
    if re.search(write_verb + r"[^|;&]*" + target, cmd):
        deny("bash: " + cmd)
    if re.search(r">>?\s*\"?(\./)?(rules/|CLAUDE\.md)", cmd):
        deny("bash: " + cmd)

sys.exit(0)
PY

exit 0
