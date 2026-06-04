#!/usr/bin/env bash
# .devcontainer/postCreate.sh
#
# Dev Container の初回作成時に 1 回だけ実行されるセットアップスクリプト。
# 何度実行しても壊れないように冪等に書く。
#
# 役割:
#   - bind-mount された /workspace を git の safe.directory に登録する
#   - Maven / npm の依存ダウンロードを先回り
#   - Claude Code 設定が想定通り読み込まれているか軽く確認

set -euo pipefail

echo "[postCreate] start"

# --- git: bind-mount のディレクトリ所有者ズレ対策 ----------------------------
# 開発者ホスト OS の uid とコンテナ内 vscode (uid 1000) が一致しない環境では
# git が "dubious ownership" エラーを出すため、安全側として /workspace を許可。
git config --global --add safe.directory /workspace || true

# --- バックエンド: 依存があれば先に解決しておく -----------------------------
# 本プロジェクトは Maven 一本化方針 (Gradle は採用しない)
if [ -f /workspace/pom.xml ]; then
  echo "[postCreate] mvn dependency:go-offline"
  (cd /workspace && mvn -B -q -DskipTests dependency:go-offline) || true
fi

# --- フロントエンド: package.json があれば npm ci --------------------------
if [ -f /workspace/package.json ]; then
  echo "[postCreate] npm install"
  (cd /workspace && (npm ci --no-audit --no-fund || npm install --no-audit --no-fund)) || true
fi

# --- Claude Code: 設定の最終整合確認 ---------------------------------------
if [ -f /workspace/.claude/settings.json ]; then
  echo "[postCreate] .claude/settings.json detected"
fi
if [ -x /workspace/.claude/hooks/block-secrets.sh ]; then
  echo "[postCreate] block-secrets.sh is executable"
else
  if [ -f /workspace/.claude/hooks/block-secrets.sh ]; then
    chmod +x /workspace/.claude/hooks/block-secrets.sh || true
    echo "[postCreate] block-secrets.sh permission fixed"
  fi
fi

echo "[postCreate] done"
