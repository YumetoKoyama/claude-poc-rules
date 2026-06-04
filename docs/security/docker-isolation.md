# Docker による外側の隔離（設計と運用手順）

最終更新: 2026-05-26

## 1. 位置づけ

本ドキュメントは [`docs/security/command-deny-policy.md`](./command-deny-policy.md) の「1.1 全体方針」で示した二段構えのうち、**外側の隔離レイヤー（Docker コンテナ）** の設計と運用手順をまとめたものである。

| 防御層 | 担当 | 配置 |
| --- | --- | --- |
| 内側: Claude Code 内のブラックリスト | `.claude/settings.json`, `.claude/hooks/block-secrets.sh` | リポジトリ内 |
| 外側: Docker コンテナによる隔離 | `.devcontainer/Dockerfile`, `.devcontainer/docker-compose.yml`, `.devcontainer/devcontainer.json` | リポジトリ内 |

「許可ホワイトリスト」運用では確認ダイアログが頻発し AI 駆動開発の効率が落ちるため、Docker で **ホスト OS と切り離す**ことで「コンテナ内であれば多少踏み外しても被害がコンテナ内に閉じる」状態を作り、その上で内側のブラックリストが致命傷だけを止める設計とする。

## 2. 構成

### 2.1 ファイル一覧

```
.devcontainer/
├─ Dockerfile          # 開発用イメージ定義 (JDK21 + Node20 + Playwright + Claude Code CLI)
├─ docker-compose.yml  # app + db (PostgreSQL 16) の 2 サービス構成
├─ devcontainer.json   # VS Code / Cursor 等の Dev Container 仕様ファイル
├─ postCreate.sh       # 初回作成時の冪等セットアップ
└─ .env.example        # GITHUB_PERSONAL_ACCESS_TOKEN / ANTHROPIC_API_KEY のサンプル
.dockerignore          # ビルドコンテキストから除外する機密・成果物
```

### 2.2 同梱物

- **JDK 21**（`mcr.microsoft.com/devcontainers/java:1-21-bookworm` ベース）
- **Maven**（apt 経由でインストール、本プロジェクトは Gradle を採用しない）
- **Node.js 20 + npm + pnpm**
- **Claude Code CLI**（`@anthropic-ai/claude-code` をグローバルインストール）
- **Playwright + Chromium / Firefox / WebKit**（`/ms-playwright` にキャッシュ）
- **PostgreSQL 16**（`db` サービスとして compose で並走）
- **MCP サーバ**: `@playwright/mcp`, `@modelcontextprotocol/server-github`

### 2.3 隔離の要点

| 項目 | 設定 | 意図 |
| --- | --- | --- |
| 実行ユーザー | `vscode` (uid 1000) | コンテナ内の sudo/su は Claude Code 側で deny。ランタイムで root にならない |
| Capabilities | `cap_drop: ALL`、必要分のみ `cap_add` | コンテナエスケープに使える権限を最小化 |
| `no-new-privileges` | `true` | setuid バイナリ経由の権限上昇を抑止 |
| Docker socket | **マウントしない** | Docker-in-Docker / コンテナエスケープを防止（`.claude/hooks/block-secrets.sh` のパターン4 と整合） |
| ネットワーク | bridge のみ、host network 非使用 | ホストの NIC 操作を許さない |
| `/tmp` | tmpfs | テスト I/O 高速化 + ホストに残さない |
| ボリューム | ソースのみ bind-mount、依存キャッシュは named volume | ホスト OS の他ディレクトリへ波及しない |
| ホスト機密 | `~/.ssh`, `~/.aws`, `~/.gnupg` 等は **一切マウントしない** | コンテナ内から触れない状態にすることで Claude も触れない |

## 3. 起動手順

### 3.1 VS Code / Cursor から起動する場合（推奨）

1. リポジトリをホスト OS にクローン
2. `.devcontainer/.env.example` を `.devcontainer/.env` にコピーし値を埋める
   （`ANTHROPIC_API_KEY` は Max / Pro プラン利用時は空のままで良い）
3. VS Code でリポジトリを開く → 右下の「Reopen in Container」を選択
4. 初回は Docker イメージのビルドと `postCreate.sh` が走る（5〜10 分）
5. ターミナルが `vscode@claude-poc-app:/workspace$` になっていれば成功
6. コンテナ内で `claude` を実行 → 初回のみ OAuth ログイン用 URL が表示されるので、ホストのブラウザで開いて Anthropic アカウント（Max / Pro 契約あり）でログイン

### 3.x Claude Code の認証について

| 契約形態 | コンテナ内での認証方法 | 設定 |
| --- | --- | --- |
| Max / Pro プラン | 初回 `claude` 起動時に OAuth ログイン | `.env` に `ANTHROPIC_API_KEY` を**設定しない** |
| API キー（従量課金） | 環境変数 `ANTHROPIC_API_KEY` を渡す | `.env` の該当行のコメントを外して値を設定 |

OAuth で得たトークンは `/home/vscode/.claude/` に保存される。compose 側でこのパスは `claude-poc-claude-home` という named volume にマウントしているため、**コンテナを `docker compose down` しても、`docker compose down -v` で volume を消さない限り認証は残る**。新しいマシンへ移行するときだけ再ログインすれば良い。

### 3.2 CLI から起動する場合

```bash
# .devcontainer ディレクトリで実行
docker compose --env-file .env up -d --build

# コンテナに入る
docker compose exec app bash

# コンテナ内で Claude Code を起動
claude
```

停止と片付け:

```bash
# サービス停止のみ
docker compose stop

# DB データも含めて完全に削除する場合
docker compose down -v
```

### 3.3 ポート

| サービス | コンテナ内 | ホスト | 用途 |
| --- | --- | --- | --- |
| Spring Boot | 8080 | 8080 | REST API |
| Vite (React) | 5173 | 5173 | フロントエンド開発サーバ |
| Storybook | 6006 | 6006 | コンポーネントカタログ（任意） |
| PostgreSQL | 5432 | 5432 | DB クライアントから接続したい場合 |

### 3.4 DB 接続情報

`docker-compose.yml` の既定値:

| 項目 | 値 |
| --- | --- |
| ホスト | `db`（app コンテナ内から）/ `localhost`（ホスト OS から） |
| ポート | 5432 |
| データベース | `appdb` |
| ユーザー | `appuser` |
| パスワード | `apppass` |

Spring Boot 用の環境変数 `SPRING_DATASOURCE_URL` / `SPRING_DATASOURCE_USERNAME` / `SPRING_DATASOURCE_PASSWORD` は compose 側で設定済み。本番値は `application-dev.yml` などで上書きしない運用とする（開発専用パスワードのため、本番想定の値は使わないこと）。

## 4. 内側ブラックリストとの整合性

`.claude/settings.json` の deny ルール、および `.claude/hooks/block-secrets.sh` のパターンとの整合は次のとおり。

- **権限昇格系（sudo / su / passwd / useradd など）の deny**
  → コンテナ内のセットアップは Dockerfile に集約しており、ランタイムでは vscode ユーザーのみで完結する。ランタイム sudo は不要なので deny で問題なし。
- **Docker socket アクセスの hook ブロック（パターン4）**
  → compose 側で socket をマウントしていないため、そもそも socket への参照経路がない。多層防御。
- **`apt purge` 系の deny**
  → 追加パッケージは Dockerfile で入れ、コンテナを作り直す運用。`apt install` は許可しているが、永続化されないため事故っても再ビルドで戻る。
- **機密ファイル参照（hook パターン3）**
  → コンテナ内には `~/.ssh`, `~/.aws`, `/etc/shadow`, `.git-credentials` 等を持ち込まない。万一参照しようとしても hook が止める。
- **CI/CD ワークフロー編集の deny（hook パターン8）**
  → bind-mount される `/workspace/.github/workflows/**` は対象。コンテナ内・外問わず保護される。
- **rm -rf 系の deny / hook パターン1**
  → bind-mount された `/workspace` 配下を `rm -rf .` 等で吹き飛ばすとホストのリポジトリも消える。hook が相対親・ホーム・ルートを止めるので致命的な事故は起きない。

## 5. 「コンテナだから大丈夫」と思ってはいけないこと

以下はコンテナ内であっても被害が出るため、内側のブラックリストが今後も必要である。

1. `/workspace` は bind-mount のためコンテナ内の `rm -rf` がホストに波及する
2. compose の `.env` に書かれたシークレットはコンテナ環境変数として残るため、Claude セッションログや外部送信で漏れる可能性がある
3. CI/CD ワークフローの改変（GitHub Actions など）は外部 CI に届くと隔離が無意味になる
4. 同じネットワーク上の `db` サービスはコンテナから自由に叩けるため、勝手な DDL や DROP は走らせ
## 7. Egress（送信側）アローリスト

### 7.1 設計

`docs/security/command-deny-policy.md` の方針では「コンテナ隔離 + ブラックリスト」で「外部送信」の制限はしない設計だったが、Claude Code が **Bypass Permissions mode**（`permissions.defaultMode: "bypassPermissions"`）で動くようになり、確認ダイアログが出なくなったため、egress を明示的に制限することにした。

実装は `ipset + iptables` のドメインベース allowlist。仕組み:

1. コンテナ起動時に root として `.devcontainer/init-firewall.sh` が走る
2. 許可ドメインを DNS 解決し、結果 IP を `ipset` のセット `allowed-ipv4` に登録
3. `iptables` で OUTPUT を `default DROP`、`allowed-ipv4` への TCP 443/80 のみ ACCEPT
4. その後 `gosu vscode tini -- sleep infinity` で vscode に降格
5. vscode は uid 1000 で `CAP_NET_ADMIN` を持たないため、iptables 規則を変更できない
6. Claude Code は `sudo`・`iptables` がいずれも `permissions.deny` で禁止されているため、ルール書き換えを試みても止まる

### 7.2 許可ドメイン

`.devcontainer/init-firewall.sh` の `ALLOWED_DOMAINS` 配列で管理。既定値:

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

### 7.3 必要なケーパビリティ

| Cap | 用途 |
| --- | --- |
| `NET_ADMIN` | init-firewall.sh が iptables / ipset を設定するため |
| `SETUID` / `SETGID` | gosu で root → vscode に降格するため |
| `SYS_ADMIN` | Playwright (Chromium sandbox) のため（既存） |

`cap_drop: ALL` で全 cap を落とした上で必要分だけ `cap_add` している。`no-new-privileges: true` も併用。

### 7.4 編集と反映

許可ドメインを追加/削除したい場合:

1. `.devcontainer/init-firewall.sh` の `ALLOWED_DOMAINS` を編集
2. VS Code で `Ctrl+Shift+P` → **`Dev Containers: Rebuild Container`**

スクリプトは bind-mount で読まれるため、image の再ビルドは不要（コンテナ再起動だけで反映）。

### 7.5 デバッグ

通信が失敗するとき:

```bash
# 現在のルールを確認 (vscode から見える)
sudo iptables -L OUTPUT -v -n   # → sudo は deny で実行不可

# Claude が iptables を確認したい場合は、ホストの PowerShell で:
docker exec --user root claude-poc-app iptables -L OUTPUT -v -n
docker exec --user root claude-poc-app ipset list allowed-ipv4 | head -20
```

新しいドメインへのアクセスが必要だと分かったら、上記 7.4 の手順で追加。

### 7.6 既知の制約

- **IP ベースなので CDN の IP 変動に弱い**。GitHub 等は IP プールが広く、初回ビルド時に解決した IP が時間とともに変わると一部接続が失敗する。その場合は Rebuild Container で再解決
- **IPv6 は完全 DROP**。allowlist 未対応のため IPv4 経由に強制
- **DNS は許可必須**。名前解決のため UDP/TCP 53 は全開。理屈上は DNS exfiltration が可能だが、Claude Code の通常用途では発生しにくい
- **手動 docker exec のデフォルトユーザーは root**。`docker compose exec app bash` は root で入る。Claude を root で動かさないために、必ず `--user vscode` を付けるか VS Code の Dev Container 経由で入ること

### 7.7 緊急脱出

allowlist が原因で開発が完全に止まったら、`.devcontainer/docker-compose.yml` の `entrypoint:` 行をコメントアウトしてコンテナを Rebuild すれば、firewall なしで起動する（一時的な退避策、本番運用では戻すこと）。
