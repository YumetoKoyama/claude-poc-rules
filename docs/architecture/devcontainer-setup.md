# AI 駆動開発向け Dev Container セットアップ（設計と運用）

最終更新: 2026-05-26

本ドキュメントは、本リポジトリで構築した **AI 駆動開発用 Dev Container** の設計判断・最終構成・運用手順・トラブルシュート集をまとめたものである。今後同種のプロジェクトを立ち上げる際の参照資料として使う。

関連ドキュメント:

- [docs/architecture/skill-orchestration.md](skill-orchestration.md) — Claude Code の skill オーケストレーション設計
- [docs/security/command-deny-policy.md](../security/command-deny-policy.md) — 内側ブラックリストの根拠
- [docs/security/docker-isolation.md](../security/docker-isolation.md) — Docker 隔離レイヤーの設計

---

## 1. 全体方針

### 1.1 二段構えのセキュリティ

AI（Claude Code）に「危ない操作も含めて自走させたい」とき、確認ダイアログ運用は効率を著しく損なう。本プロジェクトは次の二段構えで「効率」と「安全」のバランスを取る。

| 層 | 担当 | ファイル |
| --- | --- | --- |
| **外側**: Docker による隔離 | ホスト OS と切り離し、egress も制限 | `.devcontainer/Dockerfile` / `.devcontainer/docker-compose.yml` / `.devcontainer/init-firewall.sh` |
| **内側**: Claude Code 内のブラックリスト | 危険コマンド deny + hook で異常パターン検知 | `.claude/settings.json` / `.claude/hooks/block-secrets.sh` |

Claude Code は **Bypass Permissions mode**（`permissions.defaultMode: "bypassPermissions"`）で起動するため、許可ダイアログは出ない。その代わり、上記二段が「Claude が踏み外しても被害を局所化」する役割を担う。

### 1.2 設計原則

- **root 権限が必要なセットアップはすべて image build 時に済ませる** — ランタイムで sudo / su / apt purge 等を許さない
- **コンテナは開発専用**。本番デプロイ用 image は別途用意する想定
- **state は named volume に分離** — ホスト OS の他ディレクトリへ波及しない。逆に再ビルドで消えない依存キャッシュ（Maven / npm / Claude OAuth）も保持
- **bind-mount するのはソースだけ** — `/workspace` のみ
- **ホスト機密はマウントしない** — `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.git-credentials` 等は一切持ち込まない

---

## 2. 最終構成（リファレンス）

### 2.1 ファイル一覧

```
.devcontainer/
├─ Dockerfile           # 開発用 image (JDK 21 + Node 20 + Playwright + Claude Code CLI)
├─ docker-compose.yml   # app + db (PostgreSQL 16) の 2 サービス
├─ devcontainer.json    # VS Code / Cursor 用 Dev Container 仕様
├─ init-firewall.sh     # 起動時に egress allowlist (nftables) を構築
├─ postCreate.sh        # 初回作成時の冪等セットアップ (Maven/npm 依存先読み)
├─ .env.example         # GITHUB_PERSONAL_ACCESS_TOKEN 等のサンプル
└─ .env                 # 個人の秘密情報 (gitignore)
.dockerignore           # ビルドコンテキストから除外
.claude/
├─ settings.json        # deny list 194 件 + bypassPermissions + hooks 登録
└─ hooks/
   └─ block-secrets.sh  # PreToolUse hook (正規表現で危険パターン検知)
```

### 2.2 同梱物

| カテゴリ | 内容 |
| --- | --- |
| ベース | `mcr.microsoft.com/devcontainers/java:1-21-bookworm`（Debian 12 + JDK 21） |
| ビルド | **Maven**（apt 経由、本プロジェクトは Gradle 不採用） |
| ランタイム | Node.js 20 + npm + **pnpm 9**（Node 22 を要求する pnpm 10 は避ける） |
| AI ツール | Claude Code CLI（`@anthropic-ai/claude-code`） |
| E2E | Playwright + Chromium / Firefox / WebKit（`/ms-playwright` にキャッシュ） |
| DB | PostgreSQL 16（`db` サービスとして並走） |
| MCP サーバ | `@playwright/mcp`, `@modelcontextprotocol/server-github` |
| Firewall | **nftables**（iptables / ipset は使わない、後述） |
| 補助 | dnsutils（dig）, gosu, tini, jq, gnupg, postgresql-client, python3 |

### 2.3 主要な隔離設定

| 項目 | 設定 | 意図 |
| --- | --- | --- |
| 実行ユーザー | entrypoint は `root`、その後 `gosu vscode` で降格 | iptables/nftables 設定後、特権を捨てる |
| `cap_drop` | `ALL` | デフォルトで全 capability を落とす |
| `cap_add` | `SYS_ADMIN` / `NET_ADMIN` / `SETUID` / `SETGID` | Chromium sandbox + nftables + gosu に最小限必要 |
| `no-new-privileges` | `true` | setuid バイナリ経由の権限上昇を抑止 |
| Docker socket | **マウントしない** | DinD / コンテナエスケープ防止 |
| ネットワーク | bridge のみ（host network 非使用） | ホストの NIC 操作を許さない |
| `/tmp` | tmpfs | テスト I/O 高速化 + ホストに残さない |
| egress | nftables で許可ドメイン以外 DROP | LLM の意図しない外部送信を防ぐ |

### 2.4 ポート

| サービス | コンテナ内 | ホスト | 用途 |
| --- | --- | --- | --- |
| Spring Boot | 8080 | 8080 | REST API |
| Vite (React) | 5173 | 5173 | フロントエンド開発サーバ |
| Storybook | 6006 | 6006 | コンポーネントカタログ（任意） |
| PostgreSQL | 5432 | 5432 | DB クライアントからの接続 |

### 2.5 DB 接続情報（既定値）

| 項目 | 値 |
| --- | --- |
| ホスト | `db`（app コンテナ内から）/ `localhost`（ホスト OS から） |
| ポート | 5432 |
| データベース | `appdb` |
| ユーザー | `appuser` |
| パスワード | `apppass` |

> **注意**: 開発専用パスワードであり、本番では使わないこと。

---

## 3. セットアップ手順（クイックリファレンス）

### 3.1 初回（新しい開発マシン）

1. **前提**: Windows + WSL2 + Docker Desktop（WSL2 backend 有効化）/ VS Code + Dev Containers 拡張
2. リポジトリをホスト OS にクローン
3. `.devcontainer/.env.example` を `.devcontainer/.env` にコピーし、`GITHUB_PERSONAL_ACCESS_TOKEN` を埋める（PAT 要件は後述）
4. VS Code でリポジトリを開く → `Ctrl+Shift+P` → `Dev Containers: Reopen in Container`
5. 初回はイメージビルドで 5〜15 分（Playwright ブラウザ 3 種類のダウンロードが重い）
6. ターミナルが `vscode@claude-poc-app:/workspace$` になれば成功
7. `claude` を起動して OAuth ログイン（Max / Pro プランの場合、API キー不要）
8. 認証情報は `/home/vscode/.claude/` の named volume に永続化されるので、以降の再ビルドで再ログイン不要

### 3.2 通常の起動・停止

VS Code から:

- 起動: `Dev Containers: Reopen in Container`
- 停止: `Dev Containers: Reopen Folder Locally`

PowerShell から:

```powershell
cd C:\path\to\repo
docker compose -f .devcontainer\docker-compose.yml up -d
docker compose -f .devcontainer\docker-compose.yml exec --user vscode app bash
docker compose -f .devcontainer\docker-compose.yml stop
```

### 3.3 動作確認（コンテナに入った後）

```bash
java --version          # OpenJDK 21.0.8
mvn --version           # Apache Maven 3.8.x
node --version          # v20.x
pnpm --version          # 9.x（警告なし）
claude --version
npx playwright --version  # 1.x（プロンプトなし）
psql -h db -U appuser -d appdb -c '\l'

# egress 制限の動作確認
curl -sI --max-time 10 https://api.anthropic.com/ | head -1   # HTTP 200 系
curl --max-time 5 -sI https://example.com/ ; echo "exit=$?"   # exit=28 (timeout)
```

### 3.4 GitHub PAT の要件

`.devcontainer/.env` の `GITHUB_PERSONAL_ACCESS_TOKEN` に **fine-grained PAT** を設定（推奨）。Repository permissions:

| 権限 | 設定 | 理由 |
| --- | --- | --- |
| Contents | Read & Write | feature ブランチへの push |
| Pull requests | Read & Write | PR 作成・更新 |
| Issues | Read & Write | Issue 起票・更新 |
| Metadata | Read | 必須 |
| Actions | Read | CI ステータス参照 |
| Workflows | **No access** | deny ポリシーと整合（`.github/workflows/**` 編集禁止） |

加えて、`main` / `master` / `develop` には **GitHub 側で Branch protection rules を設定**しておくこと（`git push origin main` の deny と多層防御）。

---

## 4. 各ファイルの設計判断

### 4.1 Dockerfile

#### 全体構造

```
ARG → FROM → ENV → apt install → Node → npm globals → Playwright → USER → ENTRYPOINT
```

#### 重要ポイント

- **ベースイメージは `mcr.microsoft.com/devcontainers/java`**。git, curl, sudo, vscode ユーザー等が既に整備されており、Dev Container 用途で実績がある
- **NodeSource からシステム全体に Node を入れる**。同梱の nvm は対話シェル前提で AI 駆動開発には向かない
- **pnpm はバージョン固定 (`pnpm@9`)**。pnpm 10+ は Node 22 必須で、本プロジェクトの Node 20 とは非互換
- **Playwright CLI は npm global にも入れる**。`@playwright/mcp` だけだと `npx playwright` で都度インストールプロンプトが出る
- **`USER vscode` で終わる**が、compose 側で `user: "0:0"` 上書きして root 起動する（後述）
- **すべての named volume マウント先 (`~/.m2`, `~/.npm`, `~/.claude`) を image で先に作る**。これをしないと named volume が root 所有で作られ、vscode から書けない

#### apt install で含めるもの

```
ca-certificates curl dnsutils git gnupg gosu jq locales lsb-release
maven nftables python3 python3-pip postgresql-client tini tzdata unzip
+ Playwright ブラウザ依存 (libnss3, libgtk-3-0 等多数)
+ fonts-noto-cjk fonts-noto-color-emoji
```

特殊なもの:
- `gosu`: root → vscode の降格用
- `nftables`: egress allowlist の本体（iptables / ipset は不採用）
- `tini`: PID 1 として孤児プロセスとシグナルを管理
- `dnsutils`: init-firewall.sh が `dig` で許可ドメインを解決

### 4.2 docker-compose.yml

#### 重要ポイント

- **`user: "0:0"`** で root 起動。init-firewall.sh が iptables / nftables を設定するのに必要。スクリプト最終行で `gosu vscode` に降格
- **`entrypoint: ["/workspace/.devcontainer/init-firewall.sh"]`** が egress allowlist を構築するエントリポイント
- **`cap_drop: ALL` + `cap_add: SYS_ADMIN, NET_ADMIN, SETUID, SETGID`**
  - SYS_ADMIN: Chromium sandbox
  - NET_ADMIN: nftables 設定
  - SETUID / SETGID: gosu の降格
- **`no-new-privileges: true`**: setuid 経由の上昇を抑止。root → vscode への降格は「失う」方向なので問題なし
- **依存キャッシュは named volume**: `claude-poc-m2` / `claude-poc-npm` / `claude-poc-claude-home` / `claude-poc-pgdata`
- **`/tmp` は tmpfs**: 高速 + ホストに残さない

#### docker compose exec の注意

`user: "0:0"` なので `docker compose exec app bash` は **root で入る**。Claude を root で動かさないために、必ず:

- VS Code Dev Container から開く（`remoteUser: vscode` で自動的に vscode）
- または `docker compose exec --user vscode app bash`

### 4.3 devcontainer.json

#### 重要ポイント

- **`remoteUser: vscode`** だけ指定し、`containerUser` は明示しない。compose の `user: "0:0"` を尊重させ、entrypoint を root で走らせるため
- **`containerEnv: { CLAUDE_CONFIG_DIR: "/home/vscode/.claude" }`**。Claude Code が XDG_CONFIG_HOME 等の別ロケーションを参照する余地をなくし、必ず named volume 上の `/home/vscode/.claude` を使うようにする
- **`overrideCommand: false`**。compose の `command: ["sleep", "infinity"]` をそのまま尊重
- **`shutdownAction: stopCompose`**。VS Code を閉じたら db ごと止める
- **`postCreateCommand: "bash .devcontainer/postCreate.sh"`** で初回セットアップ

### 4.4 init-firewall.sh

#### 設計

1. コンテナ起動時に root として実行される（compose の entrypoint）
2. **許可ドメインを DNS 解決** し、結果 IP を nftables の named set `allowed_v4` に登録
3. **nftables ルールを適用**: OUTPUT を `default DROP`、`allowed_v4` への TCP 443/80 のみ ACCEPT
4. **`gosu vscode tini -- sleep infinity` で vscode に降格**し、コンテナの PID 1 を tini にする
5. vscode は uid 1000 で `CAP_NET_ADMIN` を持たないため、後から nftables ルールを変更できない

#### なぜ nftables？（iptables / ipset を避けた理由）

| 試した方式 | 結果 |
| --- | --- |
| iptables-nft + ipset | ✕ `Can't open socket to ipset` — nf_tables backend は ipset と非互換 |
| iptables-legacy + ipset | ✕ `Permission denied (you must be root)` — **WSL2 のカーネルに legacy x_tables モジュールがない** |
| **nftables ネイティブ（named set 機能内蔵）** | ✓ 動作 |

#### なぜ `nft flush ruleset` ではなく個別 delete か

`nft flush ruleset` は **Docker の内蔵 DNS リダイレクト用 NAT ルール（127.0.0.11 → 実 DNS）も巻き添えで削除する**。これが起きると DNS 解決が壊れ、ECONNREFUSED の嵐になる。

→ 解決: 自分が管理する `inet filter` / `ip6 filter` テーブルだけを `nft delete table` で消す。

```bash
nft delete table inet filter 2>/dev/null || true
nft delete table ip6 filter  2>/dev/null || true
```

#### なぜ `gosu` / `tini` / `sleep` を絶対パスにするか

`exec` でバイナリが見つからない場合 `set -e` で即死し、コンテナが exit する。原因切り分けに時間がかかるので、最終段の exec は必ず絶対パス:

```bash
exec /usr/sbin/gosu vscode /usr/bin/tini -- /bin/sleep infinity
```

#### `nft list ruleset | head -25` の罠

`set -o pipefail` 下で `head` が pipe を閉じると、上流の `nft` が SIGPIPE で非ゼロ exit → スクリプト全体が失敗扱い → コンテナ即死。

→ 解決: `(nft list ruleset 2>&1 || true) | awk 'NR<=25' || true` のように二重で吸収。

### 4.5 postCreate.sh

#### 役割

Dev Container の**初回作成時に 1 回だけ**実行される冪等な初期化。

- `git config --global --add safe.directory /workspace` で bind-mount の所有者ズレを許可
- `pom.xml` があれば `mvn dependency:go-offline` で依存を先回り取得
- `package.json` があれば `npm ci` を実行
- Playwright のブラウザがイメージ内のキャッシュとズレていないか確認

### 4.6 .claude/settings.json（補足）

Docker 隔離と対になる内側のブラックリスト。詳細は [command-deny-policy.md](../security/command-deny-policy.md)。

- `permissions.defaultMode: "bypassPermissions"` — 確認ダイアログをスキップ
- `permissions.deny` 194 件 — Bash / Read / Edit / Write / WebFetch の各ツールに対する deny プレフィックス
- `hooks.PreToolUse` で `block-secrets.sh` を登録 — 正規表現で危険パターンを検知

---

## 5. egress allowlist の運用

### 5.1 許可ドメインの編集

`.devcontainer/init-firewall.sh` の `ALLOWED_DOMAINS` 配列を編集。既定値:

| カテゴリ | ドメイン |
| --- | --- |
| Anthropic | api.anthropic.com / claude.ai / console.anthropic.com / statsig.anthropic.com |
| GitHub | github.com / api.github.com / codeload.github.com / raw.githubusercontent.com / objects.githubusercontent.com / uploads.github.com |
| npm | registry.npmjs.org |
| Node.js | nodejs.org / deb.nodesource.com |
| Debian APT | deb.debian.org / security.debian.org |
| Maven Central | repo1.maven.org / repo.maven.apache.org |
| Playwright | playwright.dev / cdn.playwright.dev / playwright.azureedge.net |
| PyPI | pypi.org / files.pythonhosted.org |

### 5.2 編集後の反映

スクリプトは bind-mount で読まれるので **image 再ビルドは不要**:

```powershell
docker compose -f .devcontainer\docker-compose.yml restart app
docker logs claude-poc-app | Select-String "→"   # 各ドメインが何 IP に解決されたか確認
```

### 5.3 デバッグ

```powershell
# 現在のルールを丸ごと表示 (ホストから root として)
docker exec --user root claude-poc-app nft list ruleset

# 許可セットの中身だけ
docker exec --user root claude-poc-app nft list set inet filter allowed_v4
```

### 5.4 既知の制約

- **IP ベースなので CDN の IP 変動に弱い**。GitHub / Cloudflare 等は IP プールが広く、起動時に解決した IP が時間とともにずれる場合がある。その場合は `restart` で再解決される
- **IPv6 は完全 DROP**。allowlist 未対応のため IPv4 に強制
- **DNS (UDP/TCP 53) は全開**。名前解決のため必須。理論上は DNS exfiltration が可能だが、内側ブラックリストで通常パターンは止まる

### 5.5 緊急脱出

allowlist が原因で開発が完全に止まったら、`.devcontainer/docker-compose.override.yml` に以下を置けば firewall を無効化して起動できる（一時的な退避策）:

```yaml
services:
  app:
    user: vscode
    entrypoint: ["/usr/bin/tini", "--"]
```

`docker compose down && docker compose up -d` で反映。原因解決後は override を削除すること。

---

## 6. トラブルシュート集

今回の構築で実際に踏んだ落とし穴と対処。再発時の指針。

### 6.1 `apt-get update` が GPG エラーで失敗

```
W: GPG error: https://dl.yarnpkg.com/debian stable InRelease: ...
   The following signatures couldn't be verified because the public key is not available: NO_PUBKEY 62D54FD4003F6525
E: The repository 'https://dl.yarnpkg.com/debian stable InRelease' is not signed.
```

**原因**: ベースイメージ（`mcr.microsoft.com/devcontainers/java:1-21-bookworm`）に Yarn の apt リポジトリが同梱されているが、GPG 公開鍵が期限切れ。

**対処**: 本プロジェクトは Yarn を使わない（Node は NodeSource、パッケージ管理は npm/pnpm）ので、apt-get update 前に Yarn 関連の apt 設定ファイルを削除する:

```dockerfile
RUN find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name 'yarn*' -o -name '*yarn*' \) -print -delete 2>/dev/null || true \
 && find /etc/apt/keyrings -maxdepth 1 -type f -name '*yarn*' -print -delete 2>/dev/null || true \
 && find /etc/apt/trusted.gpg.d -maxdepth 1 -type f -name '*yarn*' -print -delete 2>/dev/null || true \
 && apt-get update \
 && ...
```

### 6.2 `mvn: command not found`

**原因**: `mcr.microsoft.com/devcontainers/java` は JDK と一般ツールは入れてくれるが、**Maven は同梱されていない**（誤認しがち）。

**対処**: apt install のリストに `maven` を明示的に追加。Debian bookworm では Maven 3.8.x が入る。

### 6.3 `gradle --version` が `Could not initialize native services` で失敗

**原因**: Gradle が native-platform ライブラリを `~/.gradle/native/...` に展開しようとするが、named volume が root 所有で作られていてアクセス不能。

**根本対処**: 本プロジェクトでは **Maven 一本化** を決断し、Gradle 同梱をやめた。Spring Boot は Maven でも完全に動くため、不要な複雑性を排除した。

### 6.4 `pnpm` が Node 22+ を要求するエラー

```
warn: This version of pnpm requires at least Node.js v22.13
warn: The current version of Node.js is v20.20.2
Error [ERR_UNKNOWN_BUILTIN_MODULE]: No such built-in module: node:sqlite
```

**原因**: `npm install -g pnpm@latest` で pnpm 10+ が入るが、これは Node 22 必須。本イメージは Node 20。

**対処**: pnpm のバージョンを Node 20 互換の最新メジャー `pnpm@9` に固定。

```dockerfile
RUN npm install -g npm@latest pnpm@9
```

### 6.5 `npx playwright --version` でインストールプロンプト

```
Need to install the following packages:
playwright@1.60.0
Ok to proceed? (y) n
```

**原因**: image には `@playwright/mcp` だけ入れていて、`playwright` CLI 本体が global に入っていなかった。プロジェクト直下に package.json がない状態で `npx` を叩くと「ローカルにないからインストールするか？」と聞かれる。

**対処**: npm global インストールに `playwright` を追加。

```dockerfile
RUN npm install -g \
      @anthropic-ai/claude-code \
      @playwright/mcp \
      @modelcontextprotocol/server-github \
      playwright
```

### 6.6 named volume の権限問題（Gradle / npm 等が「書けない」）

**原因**: Docker の名前付きボリュームを image にない target dir にマウントすると、空 volume が root 所有で作られ、非 root ユーザーから書けない。

**対処**: Dockerfile で `USER vscode` の状態で `mkdir -p` し、各マウント先ディレクトリを vscode 所有で先に作る。

```dockerfile
USER vscode
WORKDIR /workspace
RUN mkdir -p \
      /home/vscode/.claude \
      /home/vscode/.m2 \
      /home/vscode/.npm
```

Docker は「volume が空の場合、image 側 target dir の中身と権限を新しい volume にコピーする」挙動なので、これで vscode 所有の空 dir が volume として作られる。

### 6.7 `iptables-legacy: Permission denied (you must be root)`

**症状**: root で起動、cap_add NET_ADMIN もある、それでも iptables-legacy が動かない。

**原因**: **WSL2 のカーネルに legacy x_tables モジュールが含まれていない**。Docker Desktop の WSL2 backend で iptables-legacy は使えない。

**対処**: nftables ネイティブに切り替え（iptables-legacy も iptables-nft + ipset も諦める）。nftables は組み込みで named set を持つので ipset 不要。

### 6.8 `iptables: Can't open socket to ipset`

**症状**: iptables-nft（Debian bookworm のデフォルト）+ ipset を組み合わせると失敗。

**原因**: iptables-nft の `-m set` 拡張が ipset と互換性がない（カーネル設定依存）。

**対処**: 6.7 と同じく nftables ネイティブに移行。

### 6.9 SIGPIPE でコンテナが即死

**症状**: init-firewall.sh が「nftables 概要」を出力する途中でコンテナが exit する。

**原因**: `nft list ruleset | head -25` の `head` が pipe を早期 close → 上流 `nft` が SIGPIPE で非ゼロ exit → `set -o pipefail` で失敗扱い → `set -e` でスクリプト即終了 → コンテナ exit。

**対処**: `head` を `awk 'NR<=25'` に置き換え、さらに `|| true` で多重ガード。

```bash
(nft list ruleset 2>&1 || true) | awk 'NR<=25 { print }' || true
```

### 6.10 firewall を有効化したら DNS が完全に死ぬ

**症状**:
```
;; communications error to 127.0.0.11#53: connection refused
Could not resolve host: api.anthropic.com
```

**原因**: `nft flush ruleset` が **Docker の組み込み DNS リダイレクト用 NAT ルール（127.0.0.11 → 実 DNS）も削除してしまう**。127.0.0.11 ローカルには listener がいないので、リダイレクトが消えると connection refused。

**対処**: 全 ruleset を flush せず、自分が管理する filter テーブルだけを delete:

```bash
nft delete table inet filter 2>/dev/null || true
nft delete table ip6 filter  2>/dev/null || true
# Docker の nat テーブルは温存される
```

### 6.11 Cloudflare 系 IP の変動でアクセスが切れる

**症状**: 起動直後は動いていたのに、しばらくしたら `api.anthropic.com` が ECONNREFUSED / timeout。

**原因**: api.anthropic.com / claude.ai 等は Cloudflare 経由で、DNS 解決のたびに違う IP が返ることがある。起動時に allowlist に入れた IP が現在の応答 IP と一致しなくなる。

**応急処置**: `docker compose -f .devcontainer\docker-compose.yml restart app` で再解決させる（init-firewall.sh が再実行され、最新の IP に更新される）。

**恒久対策（必要なら）**: `init-firewall.sh` に `ALLOWED_CIDRS` を追加し、Cloudflare の公式 IP 帯（https://www.cloudflare.com/ips-v4）を直接 allowed_v4 set に登録する。

### 6.12 PowerShell の `2>&1 | Tee-Object` が真っ赤になる

**症状**: `docker compose build app 2>&1 | Tee-Object build.log` を実行すると、Docker の進捗メッセージが全部赤いエラー表示になる。

**原因**: Docker は進捗を stderr に書き出す。PowerShell の `2>&1` で stderr を pipeline に流すと、各行が `RemoteException` オブジェクトとして扱われ、`Tee-Object` が「エラー」として表示する。

**対処**: PowerShell では `*>` で全ストリームをファイルにまとめるのが安全:

```powershell
docker compose -f .devcontainer\docker-compose.yml build app *> build.log
```

別ウィンドウで `Get-Content build.log -Wait -Tail 20` すれば進捗監視できる。

### 6.13 `docker logs ... is not running` が出続ける

**症状**: コンテナがすぐ exit して、VS Code Dev Container も `Stdin closed!` で失敗する。

**切り分け手順**:

1. `docker logs claude-poc-app` で entrypoint の出力を見る（どこで止まったか）
2. `docker inspect claude-poc-app` で `State.ExitCode` を確認
3. init-firewall.sh の各ステップに沿ってログを追う:
   - `ipset を初期化...` で停止 → 必要ツールが image にない
   - `許可ドメインを DNS 解決中...` で停止 → DNS が機能していない
   - `iptables/nftables ルールを適用...` で停止 → cap / kernel 互換性問題
   - `vscode ユーザーで起動...` で停止 → gosu / tini のパス問題

ほぼ全ての「即死」パターンは init-firewall.sh の途中で `set -e` が発火している。

### 6.14 Claude Code の `Insufficient permissions for auto-updates`

**症状**: `claude doctor` で「自動更新できない」警告。

**原因**: Dockerfile で `npm install -g @anthropic-ai/claude-code` を root として実行 → `/usr/lib/node_modules/` 配下にインストール → vscode から書けない。

**対処方針**: 本プロジェクトでは Dockerfile 経由のバージョン管理を選択（チーム全員のバージョンを揃えるため）。アップデートしたい時:

```powershell
docker compose -f .devcontainer\docker-compose.yml build --no-cache app
```

特定バージョンに固定したい場合は Dockerfile に `@2.1.152` のようにバージョン明示する。

### 6.15 Claude Code の `Background server: launchd/systemd unit installed`

**原因**: Claude Code が常駐サーバユニットを登録しようとするが、Docker コンテナには systemd がないので実際は起動しない。ユニットファイルだけ残っている。

**対処**: `claude daemon uninstall` で即削除。または次回 claude 起動時に自動で消える。

---

## 7. 内側ブラックリストとの整合

[docs/security/command-deny-policy.md](../security/command-deny-policy.md) の方針と対応関係。

| 対象 | 内側（Claude Code 設定） | 外側（コンテナ） |
| --- | --- | --- |
| 権限昇格 (sudo / su) | `permissions.deny` で禁止 | `no-new-privileges: true` で setuid 経路も塞ぐ |
| Docker socket | hook（パターン4）で参照ブロック | socket をマウントしない |
| `apt purge` | `permissions.deny` で禁止 | コンテナ廃棄前提（追加は OK） |
| 機密ファイル参照 | hook（パターン3）で `cat /.env` 等を検知 | `~/.ssh`, `~/.aws` をマウントしない |
| CI/CD ワークフロー編集 | `permissions.deny` + hook（パターン8） | bind-mount された `/workspace/.github/workflows/` を保護 |
| `rm -rf /` 系 | `permissions.deny` + hook（パターン1） | コンテナ内でも root の cap は最小化 |
| 外部送信 | hook（パターン6: env \| curl 等） | **nftables egress allowlist** ★今回のメイン |
| クラウドメタデータ (IMDS) | `WebFetch deny` + hook（パターン7） | egress allowlist で 169.254.0.0/16 も自動的に block |

---

## 8. 今後の拡張ポイント

### 8.1 ALLOWED_CIDRS の導入

現状は DNS 解決ベースなので CDN IP 変動に弱い。Cloudflare / GitHub の公式 IP 帯を CIDR で直接登録するオプションを `init-firewall.sh` に追加する。

```bash
ALLOWED_CIDRS=(
  173.245.48.0/20    # Cloudflare
  103.21.244.0/22    # Cloudflare
  # ...
  185.199.108.0/22   # GitHub Pages
)
```

### 8.2 IPv6 allowlist 対応

現状 IPv6 は完全 DROP。AAAA レコードしか持たないサービスが出てきたら対応が必要。

### 8.3 本番デプロイ用 Dockerfile

本ドキュメントは開発専用 image を扱う。本番用は別途 `Dockerfile.prod`（マルチステージ・JRE のみ・distroless）を用意する。開発と本番の image を絶対に混ぜないこと。

### 8.4 seccomp プロファイル

`SYS_ADMIN` を Chromium 用に付与しているが、これは過剰。Chromium 専用 user namespace に置き換える検討。

### 8.5 監査ログ

nftables の DROP 行に `log prefix "EGRESS_DROP: "` を追加し、何がブロックされたかを `docker logs` で追えるようにする検討（パフォーマンス影響注意）。

---

## 9. 参考リンク

- [Microsoft Dev Container Java image](https://hub.docker.com/_/microsoft-devcontainers-java)
- [Dev Containers Specification](https://containers.dev/implementors/json_reference/)
- [Anthropic: Claude Code](https://docs.claude.com/en/docs/claude-code)
- [nftables Wiki](https://wiki.nftables.org/)
- [Cloudflare IP Ranges](https://www.cloudflare.com/ips/)
- [Playwright on Linux dependencies](https://playwright.dev/docs/browsers#install-system-dependencies)
