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

# --- D-10: python3 不在時は fail-closed（deny）-----------------------------
if ! command -v python3 >/dev/null 2>&1; then
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"block-secrets: python3 が見つからないため安全側で全 Bash 実行をブロックしました（fail-closed）。python3 を導入してください。"}}
JSON
  exit 0
fi

INPUT=$(cat)

# tool_input.command を抽出。
COMMAND=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("tool_input", {}).get("command", ""))
except Exception:
    print("")
' 2>/dev/null || true)

[ -z "$COMMAND" ] && exit 0

# --- 複数行・行継続によるバイパス対策（C-1 改修）----------------------------
# grep は行単位マッチのため、`curl ... |<改行>sh` や `cmd \<改行>arg` を取り逃す。
# 行継続(\<改行>)とパイプ/論理演算子直後の改行を連結し、さらに残る改行を空白へ
# 潰した「単一行ビュー」を生成。元コマンド（^ アンカー検査用）と併せて検査する。
# 注意: 本フックは正規表現ベースの best-effort 検出層であり、変数間接参照
#       (`f=.env; cat $f`) や別インタプリタ経由 (`python -c ...`) を完全には
#       止められない。重要操作の最終防御は OS 権限・サンドボックス側に委ねる。
COMMAND_FLAT=$(printf '%s' "$COMMAND" | python3 -c '
import sys, re
s = sys.stdin.read()
s = re.sub(r"\\\n", " ", s)         # 行継続 (\ + 改行)
s = re.sub(r"([|&])\n", r"\1 ", s)   # パイプ/&& 直後の改行（パイプライン継続）
s = s.replace("\n", " ")               # 残る改行は空白へ（単一行ビュー）
sys.stdout.write(s)
' 2>/dev/null || printf '%s' "$COMMAND")
# 元（複数行・^ アンカー用）と単一行ビューの両方を検査対象にする
SCAN=$(printf '%s\n%s' "$COMMAND" "$COMMAND_FLAT")

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
if printf '%s\n' "$SCAN" | grep -qE '(^|[^a-zA-Z0-9_])(rm|unlink)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(--no-preserve-root[[:space:]]+)?(/([[:space:]]|$|\*)|~([[:space:]]|$|/)|\$HOME([[:space:]]|$|/)|\.\.([[:space:]]|/)|\./\*([[:space:]]|$))'; then
  deny "ルート/ホーム/親ディレクトリ/相対ワイルドカードへの rm はブロック対象です (cmd: ${COMMAND})"
fi

# --- パターン1b (D-08): 裸の rm -rf *、$VAR/*、先頭 ./* など無防備なワイルドカード削除 -
# 例: `rm -rf *`（カレント全消し）/ `rm -rf "$DIR"/*` / `rm -fr ./*` / `rm -rf $FOO/*`
# 具体パス配下の固定ワイルドカード（rm -rf target/*）は誤検知を避けるため、
# 「先頭が * / 変数 / ./ で始まるワイルドカード」に限定して捕捉する。
if printf '%s\n' "$SCAN" | grep -qE '(^|[^a-zA-Z0-9_])(rm|unlink)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(--no-preserve-root[[:space:]]+)?(\*([[:space:]]|$)|\$[A-Za-z_][A-Za-z0-9_]*/?\*|"\$[A-Za-z_][A-Za-z0-9_]*"/\*|\$\{[A-Za-z_][A-Za-z0-9_]*\}/?\*|\./\*)'; then
  deny "裸のワイルドカード削除 (rm -rf * / \$VAR/* / ./* 等) はブロック対象です (cmd: ${COMMAND})"
fi

# --- パターン2: curl/wget パイプを使ったリモートスクリプト実行 -------------
# 例: curl https://x | sh / curl ... | sudo bash / wget -qO- ... | bash
if printf '%s\n' "$SCAN" | grep -qE '\b(curl|wget|fetch)\b[^|]*\|[[:space:]]*(sudo[[:space:]]+|env[[:space:]]+[A-Z_]+=[^ ]*[[:space:]]+)*((ba|z|k|tc|c)?sh|python3?|perl|ruby|node)\b'; then
  deny "リモートスクリプトのパイプ実行 (curl/wget | sh など) はブロック対象です"
fi

# --- パターン3: 機密ファイル参照（cat/less/more/head/tail 等） -----------
# .env / SSH 鍵 / AWS 認証情報 / GnuPG / /etc/shadow / /etc/sudoers / id_rsa / *.pem / *.key / git credentials
if printf '%s\n' "$SCAN" | grep -qE '\b(cat|less|more|head|tail|nl|bat|view|strings|hexdump|xxd|od|grep|egrep|fgrep|rg|awk|sort|uniq|cut|dd)\b[^|;&]*((^|[^a-zA-Z0-9])\.env([^a-zA-Z0-9]|$)|/\.ssh/|/\.aws/|/\.gnupg/|/etc/shadow|/etc/sudoers|(^|[^a-zA-Z0-9])id_(rsa|ed25519|ecdsa|dsa)([^a-zA-Z0-9]|$)|\.pem([^a-zA-Z0-9]|$)|\.key([^a-zA-Z0-9]|$)|\.p12([^a-zA-Z0-9]|$)|\.pfx([^a-zA-Z0-9]|$)|\.jks([^a-zA-Z0-9]|$)|(^|[^a-zA-Z0-9])\.git-credentials|(^|[^a-zA-Z0-9])\.netrc|/\.docker/config\.json|/\.kube/config)'; then
  deny "機密ファイル (.env / SSH鍵 / AWS / GnuPG / /etc/shadow / credentials 等) の cat 系参照はブロック対象です"
fi

# --- パターン3b (D-08): .env の取り込み (source / . ビルトイン) ----------------
# 例: `source .env` / `. .env` / `source ./.env.local`
if printf '%s\n' "$SCAN" | grep -qE '(^|[;&|][[:space:]]*)(source|\.)[[:space:]]+([\w./-]*/)?\.env([^a-zA-Z0-9]|$)'; then
  deny ".env の取り込み (source .env / . .env) はブロック対象です"
fi

# --- パターン4: Docker socket 経由のエスケープ --------------------------
if printf '%s\n' "$SCAN" | grep -qE '/var/run/docker\.sock|/run/containerd/containerd\.sock|/var/run/crio/crio\.sock'; then
  deny "Docker / containerd / CRI-O socket への直接アクセスはブロック対象です"
fi

# --- パターン5: fork bomb -----------------------------------------------
if printf '%s\n' "$SCAN" | grep -qE ':\(\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|[[:space:]]*:'; then
  deny "fork bomb 様のパターンが検出されました"
fi

# --- パターン6: 全環境変数の出力（env / printenv の引数なし、または外部送信） --
# `env` 単独, `printenv` 単独, `env | curl ...`, `env | nc ...`, `env > /tmp/x` 等
if printf '%s\n' "$SCAN" | grep -qE '^[[:space:]]*(env|printenv)([[:space:]]*$|[[:space:]]*\|[[:space:]]*(sudo[[:space:]]+)?(curl|wget|nc|ncat|tee|mail|sendmail|ftp|scp|rsync)\b|[[:space:]]*>>?[[:space:]]*[^[:space:]]+)'; then
  deny "全環境変数の出力 (env / printenv 引数なし、または外部送信) はブロック対象です"
fi
# (D-08) シェル経由の env 出力: `bash -c "env"`, `sh -c 'printenv'`, `$(env)`, 引数なし env のサブシェル
if printf '%s\n' "$SCAN" | grep -qE '(ba|z|k|tc|c)?sh[[:space:]]+-c[[:space:]]+("|'"'"')[[:space:]]*(env|printenv)([[:space:]]|"|'"'"'|\|)|\$\([[:space:]]*(env|printenv)([[:space:]]*\)|[[:space:]])'; then
  deny "シェル経由の全環境変数出力 (bash -c \"env\" / \$(env) 等) はブロック対象です"
fi

# --- パターン7: クラウドメタデータ IMDS への bash 経由アクセス ------------
if printf '%s\n' "$SCAN" | grep -qiE '(169\.254\.169\.254|metadata\.google\.internal|metadata\.azure\.com|metadata\.aliyun\.com|metadata\.tencent\.com|169\.254\.170\.2|0x[aA]9[fF][eE][aA]9[fF][eE]|2852039166|fd00:ec2::254|\[fd00:ec2::254\])'; then
  deny "クラウドメタデータエンドポイント (IMDS) への Bash 経由アクセスはブロック対象です"
fi

# --- パターン8: CI/CD ワークフロー / .git の Bash 経由編集 -----------------
# 注: Edit/Write ツール経由は settings.json の deny でカバー済み。
#     ここでは Bash の sed -i / tee / > リダイレクト等で書き換えるケースを止める。
if printf '%s\n' "$SCAN" | grep -qE '(^|[^a-zA-Z0-9_])(sed -i|sed --in-place|tee|>>|>)[[:space:]]*[^|;&]*((^|[^a-zA-Z0-9])\.github/(workflows|actions)/|(^|[^a-zA-Z0-9])\.git/(config|hooks/)|(^|[^a-zA-Z0-9])\.gitlab-ci\.yml|(^|[^a-zA-Z0-9])Jenkinsfile|(^|[^a-zA-Z0-9])\.circleci/)'; then
  deny "CI/CD ワークフロー (.github/workflows・.gitlab-ci.yml・Jenkinsfile・.circleci) や .git/config / hooks への Bash 経由書き換えはブロック対象です"
fi

# --- パターン9: 破壊的な gh (GitHub CLI) サブコマンド -----------------------
# 注: settings.json の deny はプレフィックス一致のため、--admin のように
#     フラグが後方に来るケースを取り逃す。ここで位置非依存に捕捉する。
if printf '%s\n' "$SCAN" | grep -qE '\bgh[[:space:]]+(repo[[:space:]]+delete|secret[[:space:]]+(set|delete|remove)|variable[[:space:]]+delete|release[[:space:]]+delete|project[[:space:]]+delete|ssh-key[[:space:]]+delete|gpg-key[[:space:]]+delete|label[[:space:]]+delete|auth[[:space:]]+logout)\b'; then
  deny "破壊的な gh サブコマンド (repo delete / secret set|delete / release delete / project delete / key delete / label delete / auth logout 等) はブロック対象です"
fi
if printf '%s\n' "$SCAN" | grep -qE '\bgh[[:space:]]+pr[[:space:]]+merge\b[^|;&]*--admin\b'; then
  deny "gh pr merge --admin (ブランチ保護のバイパス) はブロック対象です"
fi
if printf '%s\n' "$SCAN" | grep -qE '\bgh[[:space:]]+api\b[^|;&]*(-X|--method)[[:space:]]+DELETE\b'; then
  deny "gh api による DELETE リクエストはブロック対象です"
fi

# --- パターン10 (D-08): .env への書き込みリダイレクト ----------------------
# 例: `echo SECRET=1 > .env` / `cat x >> .env` / `printf ... > ./.env.local`
# 注: Edit/Write ツール経由は settings.json の deny でカバー済み。Bash 経由を止める。
if printf '%s\n' "$SCAN" | grep -qE '>>?[[:space:]]*"?([\w./-]*/)?\.env([^a-zA-Z0-9]|$)'; then
  deny ".env ファイルへの Bash 経由書き込み (> .env / >> .env 等) はブロック対象です"
fi

# --- パターン11 (M-6): 採択ラベル(status:ready)の自己付与ブロック ----------
# 採択（status:ready 付与）は人間の行為。Claude/skill が gh で自己付与してはならない。
# 人間は自分の端末（非 Claude セッション）で実行するため影響を受けない。
# どうしても Claude に行わせる場合のみ ALLOW_ADOPT=1 を設定したセッションで再実行する。
if [ "${ALLOW_ADOPT:-}" != "1" ]; then
  if printf '%s\n' "$SCAN" | grep -qE '\bgh\b[^|;&]*(issue|pr)[^|;&]*(--add-label|--label)[^|;&]*status:ready'; then
    deny "採択ラベル status:ready の自己付与はブロック対象です（採択は人間の行為・M-6）。人手で付与してください。"
  fi
fi

# 上記いずれにも該当しなければ素通り
exit 0
