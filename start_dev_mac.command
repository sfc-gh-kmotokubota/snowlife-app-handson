#!/usr/bin/env bash
# =============================================================================
# start_dev_mac.command  (macOS 用 - アプリを手元で起動して画面を確認する)
# -----------------------------------------------------------------------------
# setup_mac.command で作った接続設定（.snowflake/config.toml）を使って、
# app/ の Next.js アプリを http://localhost:3000 で起動します。
# CoCo CLI がファイルを書き換えると、ブラウザの画面が自動で更新されます。
# 止めるときは Ctrl + C を押してください。
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/.snowflake/config.toml" ]; then
  echo "[ERROR] 接続設定がありません。先に setup_mac.command を実行してください。"
  read -n 1 -s || true
  exit 1
fi

export SNOWFLAKE_HOME="$SCRIPT_DIR/.snowflake"
cd "$SCRIPT_DIR/app"

if [ ! -d node_modules ]; then
  echo "--- 初回のみ: アプリの部品をインストールしています (npm install、1〜3 分) ---"
  npm install
fi

cat <<BANNER

============================================================
 アプリを起動します: http://localhost:3000
 止めるときは Ctrl + C
============================================================

BANNER
(sleep 5 && open "http://localhost:3000") &
exec npm run dev
