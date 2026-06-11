#!/usr/bin/env bash
# .devcontainer/init-firewall.sh
#
# 役割:
#   コンテナ起動時に root として実行され、egress (送信) アローリストを
#   nftables で構築する。許可ドメイン以外への通信は default DROP。
#   設定完了後、gosu で vscode ユーザーに降格して通常コマンドを exec する。
#
# 前提:
#   - CAP_NET_ADMIN を持っていること (compose の cap_add で付与)
#   - nftables (nft), dig, gosu, tini がインストール済み (Dockerfile で apt install)
#
# 設計判断:
#   - WSL2 のカーネルに legacy x_tables モジュールがないため、iptables-legacy も
#     iptables-nft + ipset の組み合わせも動かない。nftables ネイティブを採用する。
#   - nftables は組み込みの named set 機能を持つので ipset 不要。
#   - vscode (uid 1000) は CAP_NET_ADMIN を持たないため、設定後に nftables 規則を
#     書き換えられない。Claude Code 側 deny で nft / iptables / sudo も封じている。
#   - DNS (UDP/TCP 53) は許可しないと何も動かないので例外的に通す。
#   - established 接続は ACCEPT (応答パケットのため)。

set -euo pipefail

log() { echo "[init-firewall] $*"; }

# ---------------------------------------------------------------------------
# 1. 許可ドメイン一覧
#   必要に応じてこのリストを編集する。リスト編集後は Dev Container の再構築
#   (Rebuild Container) が必要。
# ---------------------------------------------------------------------------
ALLOWED_DOMAINS=(
  # Anthropic / Claude Code 本体
  api.anthropic.com
  claude.ai
  console.anthropic.com
  statsig.anthropic.com
  # Claude Code ネイティブインストーラの自動アップデート配信元 (claude update)
  storage.googleapis.com

  # GitHub (PR 作成・Issue 操作・git push)
  github.com
  api.github.com
  codeload.github.com
  raw.githubusercontent.com
  objects.githubusercontent.com
  uploads.github.com

  # npm レジストリ
  registry.npmjs.org

  # Node.js バイナリ・NodeSource
  nodejs.org
  deb.nodesource.com

  # Debian APT リポジトリ
  deb.debian.org
  security.debian.org

  # Maven Central
  repo1.maven.org
  repo.maven.apache.org

  # PyPI (python3 -m pip 必要時)
  pypi.org
  files.pythonhosted.org
)

# ---------------------------------------------------------------------------
# 2. 各ドメインを DNS 解決して IP リストを構築
# ---------------------------------------------------------------------------
log "許可ドメインを DNS 解決中 (${#ALLOWED_DOMAINS[@]} 件)..."
ALLOWED_IPS_ARRAY=()
RESOLVED_TOTAL=0
for domain in "${ALLOWED_DOMAINS[@]}"; do
  ips=$(dig +short +time=3 +tries=2 A "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
  if [[ -z "$ips" ]]; then
    log "  WARN: $domain の解決に失敗"
    continue
  fi
  count=0
  for ip in $ips; do
    ALLOWED_IPS_ARRAY+=("$ip")
    count=$((count + 1))
  done
  RESOLVED_TOTAL=$((RESOLVED_TOTAL + count))
  log "  $domain → $count IPs"
done
log "合計 $RESOLVED_TOTAL IP を許可リストに登録"

# 重複除去 + カンマ区切り
UNIQUE_IPS=$(printf "%s\n" "${ALLOWED_IPS_ARRAY[@]}" | sort -u)
ALLOWED_IPS_CSV=$(echo "$UNIQUE_IPS" | paste -sd, -)

# ---------------------------------------------------------------------------
# 3. Docker のローカルネットワーク (db への接続用) を取得
# ---------------------------------------------------------------------------
DOCKER_NET=$(ip -o -4 route show | awk '$1 != "default" && $1 ~ /\// {print $1; exit}')
if [[ -z "$DOCKER_NET" ]] || ! [[ "$DOCKER_NET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
  log "WARN: DOCKER_NET 取得失敗 (\"$DOCKER_NET\"). フォールバックを使用"
  DOCKER_NET="172.16.0.0/12"
fi
log "Docker ネットワーク許可: $DOCKER_NET"

# ---------------------------------------------------------------------------
# 4. nftables ルールを適用
# ---------------------------------------------------------------------------
log "nftables ルールを適用..."

# 自分が管理する filter テーブルだけを削除する。
# `nft flush ruleset` は Docker が組込 DNS リゾルバ (127.0.0.11) を NAT で
# リダイレクトするためのルールも消してしまい、コンテナ内 DNS が壊れる。
# よってここでは inet filter / ip6 filter のみをピンポイントで削除する。
nft delete table inet filter 2>/dev/null || true
nft delete table ip6 filter  2>/dev/null || true

# 許可 IP の集合が空でないかチェック (空だと nft が syntax error)
if [[ -z "$ALLOWED_IPS_CSV" ]]; then
  log "ERROR: 解決された IP が 0 件。DNS が機能していない可能性。中断。"
  exit 1
fi

# allowed_v4 set + filter chain を一気に定義
nft -f - <<NFT
table inet filter {
    set allowed_v4 {
        type ipv4_addr
        flags interval
        elements = { ${ALLOWED_IPS_CSV} }
    }

    chain input {
        type filter hook input priority 0; policy drop;
        iif "lo" accept
        ct state established,related accept
        ip saddr ${DOCKER_NET} accept
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy drop;
        oif "lo" accept
        ct state established,related accept
        ip daddr ${DOCKER_NET} accept
        udp dport 53 accept
        tcp dport 53 accept
        ip daddr @allowed_v4 tcp dport { 80, 443 } accept
    }
}

table ip6 filter {
    chain input {
        type filter hook input priority 0; policy drop;
    }
    chain forward {
        type filter hook forward priority 0; policy drop;
    }
    chain output {
        type filter hook output priority 0; policy drop;
    }
}
NFT

log "ルール適用完了"
log "nftables 概要:"
(nft list ruleset 2>&1 || true) | awk "NR<=25 { print }" || true

# ---------------------------------------------------------------------------
# 5. vscode に降格して exec
#   引数が何もなければ sleep infinity (compose の command 既定)
# ---------------------------------------------------------------------------
log "vscode ユーザーで起動..."
if [[ $# -eq 0 ]]; then
  exec /usr/sbin/gosu vscode /usr/bin/tini -- /bin/sleep infinity
else
  exec /usr/sbin/gosu vscode /usr/bin/tini -- "$@"
fi
