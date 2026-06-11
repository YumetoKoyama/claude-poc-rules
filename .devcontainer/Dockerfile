# syntax=docker/dockerfile:1.7
#
# AI 駆動開発用の開発コンテナ。
#
# 設計方針:
#   - 「Docker による外側の隔離」+「Claude Code の deny ルール」の二段構えのうち、
#     本ファイルが外側のレイヤーを担う。
#   - Spring Boot (JDK 25) + React (Node 24) + Claude Code CLI を 1 つの
#     開発用コンテナに同梱し、Claude にも開発者にも同じ環境を提供する。
#     ※ バージョンは確定スタックに準拠（BE: backend-00-stack #2 Java 25.0.3 /
#       FE: frontend-00-stack #4 Node.js 24.16.0）。
#   - root 権限が必要なセットアップは「すべてイメージビルド時に済ませる」。
#     コンテナ実行時は非 root ユーザー (vscode) で動作させ、Claude Code 内では
#     sudo / su / apt purge 等を deny しているため、ランタイムでの権限昇格は起きない。
#   - 本イメージは「開発専用」であり、本番デプロイ用イメージは別途用意する想定。

# 確定スタック準拠: Java 25（backend-00-stack #2）/ Node.js 24（frontend-00-stack #4）
# ※ mcr の Java 25 タグ（1-25-bookworm）は未公開のため、ベースは LTS 21 を使い、
#   実 JDK は後段の SDKMAN で 25.0.3 を導入して既定化する（下の「Java 25 (SDKMAN)」節）。
ARG JDK_VERSION=21
ARG NODE_VERSION=24

# ---------------------------------------------------------------------------
# ベースイメージ
#   Microsoft の Dev Container 公式 Java イメージは、JDK + 一般的な開発ツール
#   (git, curl, build-essential, vscode ユーザー, sudo 等) が同梱されており、
#   Dev Container 用途では実績が豊富なため採用。
# ---------------------------------------------------------------------------
FROM mcr.microsoft.com/devcontainers/java:1-${JDK_VERSION}-bookworm

ARG NODE_VERSION
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Asia/Tokyo

# ---------------------------------------------------------------------------
# Java 25 (SDKMAN)
#   mcr のベースイメージは JDK 21（LTS）。確定表 #2 = Java 25.0.3 に合わせるため、
#   ベースイメージ同梱の SDKMAN で Temurin 25.0.3 を導入し既定にする。
#   - ビルド時に root でダウンロード・設定する（実行時の init-firewall.sh の対象外）。
#   - sdkman_auto_answer=true で「既定にするか」の対話プロンプトを抑止する。
#   - JAVA_25_ID は確定表の確定値。パッチ更新時はこの ARG を変えるだけで追従できる。
# ---------------------------------------------------------------------------
ARG JAVA_25_ID=25.0.3-tem
RUN echo 'sdkman_auto_answer=true' >> /usr/local/sdkman/etc/config \
 && bash -lc "source /usr/local/sdkman/bin/sdkman-init.sh \
      && sdk install java ${JAVA_25_ID} \
      && sdk default java ${JAVA_25_ID}"
ENV JAVA_HOME=/usr/local/sdkman/candidates/java/current
ENV PATH=${JAVA_HOME}/bin:${PATH}

# ---------------------------------------------------------------------------
# OS パッケージ
#   - postgresql-client: コンテナ内から psql で db サービスへ接続するため
#   - python3 / python3-pip: .claude/hooks/block-secrets.sh が python3 に依存
#   - Playwright はセキュリティソフト対応のため未導入（導入時に依存ライブラリごと復元する）
#
# 注: ベースイメージには Yarn の apt リポジトリ
#     (/etc/apt/sources.list.d/yarn.list) が同梱されているが、GPG 公開鍵
#     (62D54FD4003F6525) が期限切れで apt-get update が失敗する既知問題がある。
#     本プロジェクトでは Yarn を使わない (Node は NodeSource、パッケージ管理は npm)
#     ため、apt-get update より前に該当ソースを除去する。
# ---------------------------------------------------------------------------
RUN find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name 'yarn*' -o -name '*yarn*' \) -print -delete 2>/dev/null || true \
 && find /etc/apt/keyrings -maxdepth 1 -type f -name '*yarn*' -print -delete 2>/dev/null || true \
 && find /etc/apt/trusted.gpg.d -maxdepth 1 -type f -name '*yarn*' -print -delete 2>/dev/null || true \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      dnsutils \
      git \
      gnupg \
      gosu \
      jq \
      locales \
      lsb-release \
      maven \
      nftables \
      python3 \
      python3-pip \
      postgresql-client \
      tini \
      tzdata \
      unzip \
 && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Node.js (NodeSource) を別途インストール
#   Dev Container イメージ同梱の nvm は対話シェル前提で AI 駆動開発に向かないため、
#   システム全体に Node を入れて全ユーザーから使えるようにする。
# ---------------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/* \
 && npm install -g npm@latest
# パッケージマネージャは npm に一本化（確定スタック frontend-00-stack #5 = npm /
# CI allowlist は npm・npx）。pnpm は確定スタック外のため導入しない。

# ---------------------------------------------------------------------------
# GitHub CLI (gh)
#   Issue / PR / Projects v2 の操作を gh に一本化するため、公式 apt リポジトリから
#   インストールする。
#   - インストールはイメージ「ビルド時」に行うため、実行時の nftables ファイア
#     ウォール (init-firewall.sh) の対象外。apt リポジトリ (cli.github.com) を
#     実行時の許可ドメインに足す必要はない。
#   - 実行時の gh 通信先 (github.com / api.github.com / uploads.github.com 等) は
#     init-firewall.sh の許可ドメインに既に含まれている。
#   - 認証はランタイムで GH_TOKEN 環境変数 (docker-compose.yml が PAT をマッピング)
#     を使う。gh は GITHUB_PERSONAL_ACCESS_TOKEN ではなく GH_TOKEN を参照する。
# ---------------------------------------------------------------------------
RUN mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# 注: Playwright（playwright CLI / @playwright/mcp / ブラウザバイナリ）は
# セキュリティソフト対応のため未導入。導入時は git 履歴の Playwright ブロックを復元する。


# ---------------------------------------------------------------------------
# vscode ユーザーの作業環境
#   ベースイメージで作成済みの uid 1000 / gid 1000 の vscode ユーザーをそのまま使う。
#   - /workspace : compose で bind-mount される作業ディレクトリ
#   - ~/.npm     : npm のキャッシュを named volume にマウントしてビルド高速化
#   - ~/.m2      : Maven ローカルリポジトリも named volume にする
#   - ~/.claude  : Claude Code の OAuth トークン保存先
#
# 重要: named volume が初回マウントされる際、Docker は「image 側の target dir の
# 中身と権限を新規 volume にコピーする」挙動を取る。逆に言うと、image に該当 dir
# が存在しないと、空 volume が root 所有で作られ、vscode ユーザーが書けず
# 各種ツールが権限エラーで落ちる。よって、ここで volume のマウント先となる
# 全 dir を vscode 所有で先に作っておく。
# ---------------------------------------------------------------------------
USER vscode
WORKDIR /workspace

RUN mkdir -p \
      /home/vscode/.claude \
      /home/vscode/.m2 \
      /home/vscode/.npm

# ---------------------------------------------------------------------------
# Claude Code CLI（ネイティブインストーラ）
#   旧方式（root の npm install -g）では、実行時に vscode ユーザーが
#   /usr/lib/node_modules へ書き込めず `claude update` が権限エラーで失敗していた。
#   ネイティブインストーラは vscode ユーザーの $HOME 配下
#   (~/.local/bin/claude + ~/.local/share/claude) に完結するため、
#   コンテナ内から sudo なしで自動アップデートできる。
#   - 実行時のアップデート通信先: claude.ai / storage.googleapis.com
#     （init-firewall.sh の許可ドメインに登録済みであること）
#   - コンテナを再作成するとイメージビルド時点の最新版に戻る（その後
#     `claude update` で再追従可能）。
#   GitHub 操作（Issue / PR / Projects）は gh CLI に一本化済みのため、
#   MCP サーバの npm パッケージは導入しない（.mcp.json も廃止済み）。
# ---------------------------------------------------------------------------
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH=/home/vscode/.local/bin:${PATH}

# ---------------------------------------------------------------------------
# エントリポイント
#   tini を PID 1 にして孤児プロセスとシグナル処理を健全に保つ。
#   compose で `command: sleep infinity` を使うので、ここでは defaults だけ持たせる。
# ---------------------------------------------------------------------------
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]
