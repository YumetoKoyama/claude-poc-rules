#!/usr/bin/env bash
# .claude/hooks/block-secrets.sh
#
# 役割:
#   Claude Code の PreToolUse(Bash) フック。
#   settings.json の permissions.deny は Bash の "プレフィックスマッチ" であり、
#   `curl ... | sh` のようなパイプ込みパターンや、`cat <任意の機密パス>` のような
#   サブ文字列マッチを正しく止められない。本スクリプトはシェル側で grep ベースの
#   パターン検査を行い、危険コマンドを上位でブロックする。
#
# 入出力:
#   stdin  : Claude Code が渡す PreToolUse の JSON
#   stdout : 通常時は何も出力せず exit 0。ブロック時は
#            {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#             "permissionDecision":"deny","permissionDecisionReason":"..."}}
#            の JSON を出力して exit 0。
#
# 注意:
#   - 依存は bash + grep + python3 のみ（jq は不要、なくても動く）
#   - 誤検知より見落としを避ける方針だが、ホワイトリスト的に明らかな安全パターンは
#     除外する。誤検知が出たら本ファイルを編集して調整すること。

set -u

INPUT=$(cat)

# tool_input.command を抽出。python3 がなければ素直に空を返し、何もブロックしない。
COMMAND=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("tool_input", {}).get("command", ""))
except Exception:
    print("")
' 2>/dev/null || true)

[ -z "$COMMAND" ] && exit 0

# deny: 理由を受け取り PreToolUse の deny JSON を出力して exit
deny() {
  local reason="$1"
  # JSON エスケープ（python に任せる）
  local esc
  esc=$(printf '%s' "$reason" | python3 -c '
import json, sys
print(json.dumps(sys.stdin.read())[1:-1])
' 2>/dev/null || printf '%s' "$reason")
  cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"$esc"}}
JSON
  exit 0
}

# --- パターン1: ルート/ホーム/相対ワイルドカードへの rm -rf 系 -------------
# 許可される対象: ./node_modules、./target、./build、/tmp/foo、相対パスの具体名等
# ブロック対象  : /、/*、~、~/*、$HOME、$HOME/*、../、./*
if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_])(rm|unlink)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(--no-preserve-root[[:space:]]+)?(/([[:space:]]|$|\*)|~([[:space:]]|$|/)|\$HOME([[:space:]]|$|/)|\.\.([[:space:]]|/)|\./\*([[:space:]]|$))'; then
  deny "ルート/ホーム/親ディレクトリ/相対ワイルドカードへの rm はブロック対象です (cmd: ${COMMAND})"
fi

# --- パターン2: curl/wget パイプを使ったリモートスクリプト実行 -------------
# 例: curl https://x | sh / curl ... | sudo bash / wget -qO- ... | bash
if echo "$COMMAND" | grep -qE '\b(curl|wget|fetch)\b[^|]*\|[[:space:]]*(sudo[[:space:]]+|env[[:space:]]+[A-Z_]+=[^ ]*[[:space:]]+)*((ba|z|k|tc|c)?sh|python3?|perl|ruby|node)\b'; then
  deny "リモートスクリプトのパイプ実行 (curl/wget | sh など) はブロック対象です"
fi

# --- パターン3: 機密ファイル参照（cat/less/more/head/tail 等） -----------
# .env / SSH 鍵 / AWS 認証情報 / GnuPG / /etc/shadow / /etc/sudoers / id_rsa / *.pem / *.key / git credentials
if echo "$COMMAND" | grep -qE '\b(cat|less|more|head|tail|nl|bat|view|strings|hexdump|xxd|od)\b[^|;&]*((^|[^a-zA-Z0-9])\.env([^a-zA-Z0-9]|$)|/\.ssh/|/\.aws/|/\.gnupg/|/etc/shadow|/etc/sudoers|(^|[^a-zA-Z0-9])id_(rsa|ed25519|ecdsa|dsa)([^a-zA-Z0-9]|$)|\.pem([^a-zA-Z0-9]|$)|\.key([^a-zA-Z0-9]|$)|\.p12([^a-zA-Z0-9]|$)|\.pfx([^a-zA-Z0-9]|$)|\.jks([^a-zA-Z0-9]|$)|(^|[^a-zA-Z0-9])\.git-credentials|(^|[^a-zA-Z0-9])\.netrc|/\.docker/config\.json|/\.kube/config)'; then
  deny "機密ファイル (.env / SSH鍵 / AWS / GnuPG / /etc/shadow / credentials 等) の cat 系参照はブロック対象です"
fi

# --- パターン4: Docker socket 経由のエスケープ --------------------------
if echo "$COMMAND" | grep -qE '/var/run/docker\.sock|/run/containerd/containerd\.sock|/var/run/crio/crio\.sock'; then
  deny "Docker / containerd / CRI-O socket への直接アクセスはブロック対象です"
fi

# --- パターン5: fork bomb -----------------------------------------------
if echo "$COMMAND" | grep -qE ':\(\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|[[:space:]]*:'; then
  deny "fork bomb 様のパターンが検出されました"
fi

# --- パターン6: 全環境変数の出力（env / printenv の引数なし、または外部送信） --
# `env` 単独, `printenv` 単独, `env | curl ...`, `env | nc ...`, `env > /tmp/x` 等
if echo "$COMMAND" | grep -qE '^[[:space:]]*(env|printenv)([[:space:]]*$|[[:space:]]*\|[[:space:]]*(sudo[[:space:]]+)?(curl|wget|nc|ncat|tee|mail|sendmail|ftp|scp|rsync)\b|[[:space:]]*>>?[[:space:]]*[^[:space:]]+)'; then
  deny "全環境変数の出力 (env / printenv 引数なし、または外部送信) はブロック対象です"
fi

# --- パターン7: クラウドメタデータ IMDS への bash 経由アクセス ------------
if echo "$COMMAND" | grep -qE '(169\.254\.169\.254|metadata\.google\.internal|metadata\.azure\.com|metadata\.aliyun\.com|metadata\.tencent\.com|169\.254\.170\.2)'; then
  deny "クラウドメタデータエンドポイント (IMDS) への Bash 経由アクセスはブロック対象です"
fi

# --- パターン8: CI/CD ワークフロー / .git の Bash 経由編集 -----------------
# 注: Edit/Write ツール経由は settings.json の deny でカバー済み。
#     ここでは Bash の sed -i / tee / > リダイレクト等で書き換えるケースを止める。
if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_])(sed -i|sed --in-place|tee|>>|>)[[:space:]]*[^|;&]*((^|[^a-zA-Z0-9])\.github/(workflows|actions)/|(^|[^a-zA-Z0-9])\.git/(config|hooks/)|(^|[^a-zA-Z0-9])\.gitlab-ci\.yml|(^|[^a-zA-Z0-9])Jenkinsfile|(^|[^a-zA-Z0-9])\.circleci/)'; then
  deny "CI/CD ワークフロー (.github/workflows・.gitlab-ci.yml・Jenkinsfile・.circleci) や .git/config / hooks への Bash 経由書き換えはブロック対象です"
fi

# --- パターン9: 破壊的な gh (GitHub CLI) サブコマンド -----------------------
# 注: settings.json の deny はプレフィックス一致のため、--admin のように
#     フラグが後方に来るケースを取り逃す。ここで位置非依存に捕捉する。
if echo "$COMMAND" | grep -qE '\bgh[[:space:]]+(repo[[:space:]]+delete|secret[[:space:]]+(set|delete|remove)|variable[[:space:]]+delete|release[[:space:]]+delete|project[[:space:]]+delete|ssh-key[[:space:]]+delete|gpg-key[[:space:]]+delete|label[[:space:]]+delete|auth[[:space:]]+logout)\b'; then
  deny "破壊的な gh サブコマンド (repo delete / secret set|delete / release delete / project delete / key delete / label delete / auth logout 等) はブロック対象です"
fi
if echo "$COMMAND" | grep -qE '\bgh[[:space:]]+pr[[:space:]]+merge\b[^|;&]*--admin\b'; then
  deny "gh pr merge --admin (ブランチ保護のバイパス) はブロック対象です"
fi
if echo "$COMMAND" | grep -qE '\bgh[[:space:]]+api\b[^|;&]*(-X|--method)[[:space:]]+DELETE\b'; then
  deny "gh api による DELETE リクエストはブロック対象です"
fi

# 上記いずれにも該当しなければ素通り
exit 0
