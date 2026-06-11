#!/usr/bin/env bash
# .claude/hooks/block-force-push.sh
#
# 役割:
#   Claude Code の PreToolUse フック。Claude 実行中（CI 含む）の
#   git の force push を一律ブロックする。
#   検出対象（git push のセグメント内に限定して判定）:
#     - -f / 短縮オプションクラスタ内の f（例: -fu）
#     - --force / --force-with-lease / --force-if-includes
#     - 先頭に + を付けた refspec（例: git push origin +main）
#     - --mirror（参照を強制更新・削除するため危険）
#
# 方針:
#   - 履歴の上書き（force push）は人手で行う。フックは Claude セッション内の
#     Bash 実行に対してのみ働くため、人が手元のターミナルから行う force push は
#     一切影響を受けない。
#
# エスケープハッチ:
#   環境変数 ALLOW_FORCE_PUSH=1 を設定したセッションでは許可する
#   （人が明示的に Claude へ force push を手伝わせたい場合）。
#   スキル/CI の自動実行はフラグを立てないため常にブロックされる。
#
# 入出力:
#   stdin  : Claude Code が渡す PreToolUse の JSON
#   stdout : 通常は無出力で exit 0。ブロック時は permissionDecision=deny の JSON を出力。
#
# 注意:
#   - 依存は bash + python3。python3 が無い場合はフェイルオープン（block-secrets.sh / protect-canon.sh と同方針）。
#   - settings.json の deny（前方一致）では --force-with-lease や +refspec を取りこぼすため、本フックで一元化している。

set -u

# --- エスケープハッチ -------------------------------------------------------
if [ "${ALLOW_FORCE_PUSH:-}" = "1" ]; then
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

if d.get("tool_name", "") != "Bash":
    sys.exit(0)

ti = d.get("tool_input", {}) or {}
cmd = ti.get("command", "") or ""

# シェルのセパレータでセグメント分割し、git push のセグメント内だけで判定する
# （例: `git push origin main && echo --force` の echo 側を誤検出しないため）
segments = re.split(r"(?:&&|\|\||[;|\n])", cmd)

re_git_push    = re.compile(r"\bgit\b[^\n]*\bpush\b")
re_force_long  = re.compile(r"--force\b")            # --force / --force-with-lease / --force-if-includes を包含
re_mirror      = re.compile(r"--mirror\b")
re_force_short = re.compile(r"(^|\s)-[A-Za-z0-9]*f[A-Za-z0-9]*(\s|=|$)")  # -f / -fu 等
re_force_plus  = re.compile(r"(^|\s)\+\S+")          # +refspec（先頭 + の強制更新）

def detect(seg):
    if not re_git_push.search(seg):
        return None
    if re_force_long.search(seg):
        return "--force / --force-with-lease"
    if re_mirror.search(seg):
        return "--mirror"
    # 短縮フラグ・+refspec は push 以降の引数に限定して判定
    after = seg.split("push", 1)[1] if "push" in seg else seg
    after = " " + after
    if re_force_short.search(after):
        return "-f"
    if re_force_plus.search(after):
        return "+refspec"
    return None

hit = None
seg_hit = ""
for seg in segments:
    kind = detect(seg)
    if kind:
        hit = kind
        seg_hit = seg.strip()
        break

if hit:
    reason = (
        "force push は Claude による実行を禁止しています"
        "（検出: %s / コマンド: %s）。"
        "履歴の上書きが必要な場合は人手で行ってください。"
        "どうしても Claude に実行させる場合のみ ALLOW_FORCE_PUSH=1 を"
        "設定したセッションで再実行してください。"
        % (hit, seg_hit)
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)

sys.exit(0)
PY

exit 0
