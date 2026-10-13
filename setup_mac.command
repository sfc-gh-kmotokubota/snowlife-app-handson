#!/usr/bin/env bash
# =============================================================================
# setup_mac.command  (macOS 用 - 前提チェック / PAT 自動生成 / 環境構築 / cortex 起動)
# -----------------------------------------------------------------------------
# 接続設定はこのフォルダの .snowflake/ に作ります。既存の ~/.snowflake/ には触れません。
#
# 起動方法: ターミナルで bash setup_mac.command
#   (ZIP でダウンロードした .command は Gatekeeper によりダブルクリックでは開けない)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SANDBOX_HOME="$SCRIPT_DIR"
PAT_NAME="CORTEX_HANDSON_PAT"
CONFIG_FILE="$SANDBOX_HOME/.snowflake/config.toml"
LOG_DIR="$SANDBOX_HOME/.temp"
export SNOWFLAKE_HOME="$SANDBOX_HOME/.snowflake"

pause_exit() {
  echo ""
  echo "何かキーを押すと終了します。"
  read -n 1 -s || true
  exit 1
}

if [ ! -f "$SANDBOX_HOME/catchup.sql" ]; then
  echo "[ERROR] このスクリプトは snowlife-app-handson-main/ の直下に置いて実行してください。"
  echo "        現在の場所: $SANDBOX_HOME"
  pause_exit
fi

cat <<BANNER

============================================================
 スノー生命 アプリ開発ハンズオン セットアップ (macOS)
============================================================

--- 前提チェック ---
BANNER

check_ng=0
if command -v cortex >/dev/null 2>&1; then
  echo "[OK] cortex (CoCo CLI)"
else
  echo "[NG] cortex (CoCo CLI) が見つかりません。セットアップガイドの手順でインストールしてください。"
  check_ng=1
fi

if command -v snow >/dev/null 2>&1; then
  snow_ver=$(snow --version 2>/dev/null | sed -E 's/.*version: *//')
  snow_major=$(echo "$snow_ver" | cut -d. -f1)
  snow_minor=$(echo "$snow_ver" | cut -d. -f2)
  if [ "$(( ${snow_major:-0} * 100 + ${snow_minor:-0} ))" -lt 329 ]; then
    echo "[NG] snow のバージョンが古いです ($snow_ver)。3.29 以上に更新してください。"
    check_ng=1
  else
    echo "[OK] snow (Snowflake CLI) $snow_ver"
  fi
else
  echo "[NG] snow (Snowflake CLI) が見つかりません。セットアップガイドの手順でインストールしてください。"
  check_ng=1
fi

if command -v node >/dev/null 2>&1; then
  echo "[OK] node (Node.js) $(node -v)"
else
  echo "[NG] node (Node.js) が見つかりません。Node.js LTS 版をインストールしてください。"
  check_ng=1
fi

if command -v npm >/dev/null 2>&1; then
  echo "[OK] npm"
else
  echo "[NG] npm が見つかりません。Node.js を入れ直してください。"
  check_ng=1
fi

if [ "$check_ng" = "1" ]; then
  echo ""
  echo "[ERROR] 足りないものがあります。上の [NG] を解決してから、もう一度実行してください。"
  pause_exit
fi
echo ""

# =============================================================================
# PAT 生成
# =============================================================================
generate_pat() {
  local sf_account="$1" sf_user="$2" sf_password="$3"

  echo "--- PAT を生成しています... ---"
  SNOWFLAKE_PASSWORD="$sf_password" snow sql --temporary-connection \
    --account "$sf_account" --user "$sf_user" \
    -q "ALTER USER IF EXISTS $sf_user REMOVE PAT $PAT_NAME" >/dev/null 2>&1 || true

  local pat_result
  pat_result=$(SNOWFLAKE_PASSWORD="$sf_password" snow sql --temporary-connection \
    --account "$sf_account" --user "$sf_user" \
    -q "ALTER USER ADD PAT $PAT_NAME DAYS_TO_EXPIRY = 30 MINS_TO_BYPASS_NETWORK_POLICY_REQUIREMENT = 1440 COMMENT = 'CoCo CLI app handson auto-generated token'" \
    --format json 2>&1) || {
    echo "[ERROR] PAT の生成に失敗しました:"
    echo "$pat_result"
    echo ""
    echo "考えられる原因:"
    echo "  - パスワードが間違っている"
    echo "  - PAT の上限 (15個) に達している"
    echo "  - アカウント識別子が間違っている"
    pause_exit
  }

  local token_secret
  token_secret=$(echo "$pat_result" | tr -d '\n\r ' | grep -o '"token_secret":"[^"]*"' | head -1 | cut -d'"' -f4)
  if [ -z "$token_secret" ]; then
    echo "[ERROR] トークンの抽出に失敗しました。"
    pause_exit
  fi

  mkdir -p "$SANDBOX_HOME/.snowflake"
  printf 'default_connection_name = "handson"\n\n[connections.handson]\naccount = "%s"\nuser = "%s"\npassword = "%s"\nrole = "ACCOUNTADMIN"\nwarehouse = "COMPUTE_WH"\n' \
    "$sf_account" "$sf_user" "$token_secret" > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  echo "--- PAT 生成完了。接続設定を作成しました ---"
}

ask_and_generate() {
  read -rp "アカウント識別子 (例: ORGNAME-ACCOUNTNAME): " SF_ACCOUNT
  read -rp "ユーザ名: " SF_USER
  read -rsp "パスワード: " SF_PASSWORD
  echo ""
  if [ -z "$SF_ACCOUNT" ] || [ -z "$SF_USER" ] || [ -z "$SF_PASSWORD" ]; then
    echo "[ERROR] すべての項目を入力してください。"
    pause_exit
  fi
  generate_pat "$SF_ACCOUNT" "$SF_USER" "$SF_PASSWORD"

  echo "--- 接続テスト中... ---"
  if ! snow connection test -c handson; then
    echo "[ERROR] 接続テストに失敗しました。"
    echo "  PAT のネットワークポリシー回避は 24 時間有効です。時間切れの場合はもう一度実行してください。"
    pause_exit
  fi
  echo ""
}

# =============================================================================
# 接続設定
# =============================================================================
if [ -f "$CONFIG_FILE" ]; then
  echo "既存の接続設定が見つかりました。接続テストを実行します..."
  if snow connection test -c handson >/dev/null 2>&1; then
    echo "--- 接続 OK ---"
    echo ""
  else
    echo "接続テストに失敗しました。PAT を作り直します。"
    echo ""
    ask_and_generate
  fi
else
  echo "Snowflake の接続情報を入力してください。"
  echo "PAT (Programmatic Access Token) を自動で作り、接続設定を作成します。"
  echo ""
  ask_and_generate
fi

# =============================================================================
# 環境構築 (catchup.sql) - Cortex Agent がまだなければ実行する
# =============================================================================
if snow sql -c handson -q "DESCRIBE AGENT SNOWLIFE_HANDSON_DB.AI.SALES_AGENT" >/dev/null 2>&1; then
  echo "--- 環境は構築済みです (SNOWLIFE_HANDSON_DB.AI.SALES_AGENT) ---"
else
  mkdir -p "$LOG_DIR"
  echo "--- 環境を構築しています (catchup.sql、約 5 分) ---"
  echo "    データ・Cortex Search・セマンティックビュー・Cortex Agent をまとめて作ります。"
  echo "    ログ: .temp/catchup.log"
  if ! snow sql -c handson -f "$SANDBOX_HOME/catchup.sql" > "$LOG_DIR/catchup.log" 2>&1; then
    echo "[ERROR] 環境構築に失敗しました。ログの最後の部分:"
    tail -n 30 "$LOG_DIR/catchup.log"
    pause_exit
  fi
  echo "--- 環境構築が完了しました ---"
fi
echo ""

# =============================================================================
# cortex 起動
# =============================================================================
echo "--- CoCo CLI を起動します ---"
echo "    アプリの画面を見るには、別のターミナルで start_dev_mac.command を実行してください。"
echo ""
HOME="$SANDBOX_HOME" \
exec cortex \
  -c handson \
  -w "$SANDBOX_HOME" \
  --setting-sources project \
  --no-mcp \
  --no-auto-update
