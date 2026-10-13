@echo off
chcp 65001 >nul

REM =============================================================================
REM setup_win.bat  (Windows 用 - 前提チェック / PAT 自動生成 / 環境構築 / cortex 起動)
REM =============================================================================
REM ダブルクリック時にウィンドウが即閉じるのを防ぐため、
REM 初回実行時は cmd /k で自分自身を再起動する。
REM 2回目以降 (SETUP_GUARD=1) は本体処理を実行する。

if "%SETUP_GUARD%"=="1" goto :main

set "SETUP_GUARD=1"
cmd /k "%~f0"
exit /b

:main
setlocal enabledelayedexpansion

cd /d "%~dp0"
set "SANDBOX_HOME=%~dp0"
if "!SANDBOX_HOME:~-1!"=="\" set "SANDBOX_HOME=!SANDBOX_HOME:~0,-1!"

set "PAT_NAME=CORTEX_HANDSON_PAT"
set "CONFIG_FILE=!SANDBOX_HOME!\.snowflake\config.toml"
set "LOG_DIR=!SANDBOX_HOME!\.temp"
REM snow が SQL ファイル（日本語を含む）を UTF-8 として読むようにする
set "PYTHONUTF8=1"

REM --- 前提チェック ---
if not exist "!SANDBOX_HOME!\catchup.sql" (
    echo [ERROR] このバッチは snowlife-app-handson-main の直下に置いて実行してください。
    echo         現在の場所: !SANDBOX_HOME!
    goto :eof
)

echo.
echo ============================================================
echo  スノー生命 アプリ開発ハンズオン セットアップ ^(Windows^)
echo ============================================================
echo.
echo --- 前提チェック ---

set "CHECK_NG=0"
where cortex >nul 2>nul
if errorlevel 1 (
    echo [NG] cortex ^(CoCo CLI^) が見つかりません。セットアップガイドの手順でインストールしてください。
    set "CHECK_NG=1"
) else (
    echo [OK] cortex ^(CoCo CLI^)
)

where snow >nul 2>nul
if errorlevel 1 (
    echo [NG] snow ^(Snowflake CLI^) が見つかりません。セットアップガイドの手順でインストールしてください。
    set "CHECK_NG=1"
) else (
    set "SNOW_VER="
    for /f "tokens=*" %%V in ('snow --version 2^>nul') do set "SNOW_VER=%%V"
    set "SNOW_VER=!SNOW_VER:Snowflake CLI version: =!"
    set "SNOW_MAJOR=0"
    set "SNOW_MINOR=0"
    for /f "tokens=1,2 delims=." %%A in ("!SNOW_VER!") do (
        set "SNOW_MAJOR=%%A"
        set "SNOW_MINOR=%%B"
    )
    set /a "SNOW_NUM=!SNOW_MAJOR! * 100 + !SNOW_MINOR!" 2>nul
    if !SNOW_NUM! LSS 329 (
        echo [NG] snow のバージョンが古いです ^(!SNOW_VER!^)。3.29 以上に更新してください。
        echo      winget upgrade Snowflake.SnowflakeCLI
        set "CHECK_NG=1"
    ) else (
        echo [OK] snow ^(Snowflake CLI^) !SNOW_VER!
    )
)

where node >nul 2>nul
if errorlevel 1 (
    echo [NG] node ^(Node.js^) が見つかりません。Node.js LTS 版をインストールしてください。
    set "CHECK_NG=1"
) else (
    for /f "tokens=*" %%V in ('node -v') do echo [OK] node ^(Node.js^) %%V
)

where npm >nul 2>nul
if errorlevel 1 (
    echo [NG] npm が見つかりません。Node.js を入れ直してください。
    set "CHECK_NG=1"
) else (
    echo [OK] npm
)

if "!CHECK_NG!"=="1" (
    echo.
    echo [ERROR] 足りないものがあります。上の [NG] を解決してから、もう一度実行してください。
    goto :eof
)
echo.

REM =============================================================================
REM 接続設定 (既存設定が使えればそのまま、使えなければ PAT を作り直す)
REM =============================================================================
set "SNOWFLAKE_HOME=!SANDBOX_HOME!\.snowflake"

if exist "!CONFIG_FILE!" (
    echo 既存の接続設定が見つかりました。接続テストを実行します...
    snow connection test -c handson >nul 2>nul
    if !errorlevel! equ 0 (
        echo --- 接続 OK ---
        echo.
        goto :catchup
    )
    echo 接続テストに失敗しました。PAT を作り直します。
    echo.
) else (
    echo Snowflake の接続情報を入力してください。
    echo PAT ^(Programmatic Access Token^) を自動で作り、接続設定を作成します。
    echo.
)

set /p "SF_ACCOUNT=アカウント識別子 (例: ORGNAME-ACCOUNTNAME): "
set /p "SF_USER=ユーザ名: "

set "SF_PASSWORD="
echo|set /p="パスワード: "
powershell -NoProfile -Command "$p = Read-Host -AsSecureString; $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($p); [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)" > "%TEMP%\pw_tmp.txt"
set /p SF_PASSWORD=<"%TEMP%\pw_tmp.txt"
del "%TEMP%\pw_tmp.txt" >nul 2>nul
echo.

if "!SF_ACCOUNT!"=="" goto :missing_input
if "!SF_USER!"=="" goto :missing_input
if "!SF_PASSWORD!"=="" goto :missing_input

call :generate_pat
if errorlevel 1 goto :eof

echo --- 接続テスト中... ---
snow connection test -c handson
if errorlevel 1 (
    echo [ERROR] 接続テストに失敗しました。
    echo   PAT のネットワークポリシー回避は 24 時間有効です。時間切れの場合はもう一度実行してください。
    goto :eof
)
echo.

REM =============================================================================
REM 環境構築 (catchup.sql) - Cortex Agent がまだなければ実行する
REM =============================================================================
:catchup
snow sql -c handson -q "DESCRIBE AGENT SNOWLIFE_HANDSON_DB.AI.SALES_AGENT" >nul 2>nul
if !errorlevel! equ 0 (
    echo --- 環境は構築済みです ^(SNOWLIFE_HANDSON_DB.AI.SALES_AGENT^) ---
    echo.
    goto :launch_cortex
)

if not exist "!LOG_DIR!" mkdir "!LOG_DIR!"
echo --- 環境を構築しています ^(catchup.sql、約 5 分^) ---
echo     データ・Cortex Search・セマンティックビュー・Cortex Agent をまとめて作ります。
echo     ログ: .temp\catchup.log
snow sql -c handson -f "!SANDBOX_HOME!\catchup.sql" > "!LOG_DIR!\catchup.log" 2>&1
if errorlevel 1 (
    echo [ERROR] 環境構築に失敗しました。ログの最後の部分:
    powershell -NoProfile -Command "Get-Content -Path '!LOG_DIR!\catchup.log' -Tail 30 -Encoding UTF8"
    goto :eof
)
echo --- 環境構築が完了しました ---
echo.
goto :launch_cortex

:missing_input
echo [ERROR] すべての項目を入力してください。
goto :eof

REM =============================================================================
REM PAT 生成関数
REM =============================================================================
:generate_pat
echo --- PAT を生成しています... ---

set "SNOWFLAKE_PASSWORD=!SF_PASSWORD!"
snow sql --temporary-connection --account "!SF_ACCOUNT!" --user "!SF_USER!" -q "ALTER USER IF EXISTS !SF_USER! REMOVE PAT !PAT_NAME!" >nul 2>nul

snow sql --temporary-connection --account "!SF_ACCOUNT!" --user "!SF_USER!" -q "ALTER USER ADD PAT !PAT_NAME! DAYS_TO_EXPIRY = 30 MINS_TO_BYPASS_NETWORK_POLICY_REQUIREMENT = 1440 COMMENT = 'CoCo CLI app handson auto-generated token'" --format json > "%TEMP%\pat_result.txt" 2>&1
if errorlevel 1 (
    echo [ERROR] PAT の生成に失敗しました:
    type "%TEMP%\pat_result.txt"
    echo.
    echo 考えられる原因:
    echo   - パスワードが間違っている
    echo   - PAT の上限 ^(15個^) に達している
    echo   - アカウント識別子が間違っている
    del "%TEMP%\pat_result.txt" >nul 2>nul
    set "SNOWFLAKE_PASSWORD="
    exit /b 1
)

set "TOKEN_SECRET="
> "%TEMP%\extract_token.ps1" echo $j = Get-Content '%TEMP%\pat_result.txt' -Raw ^| ConvertFrom-Json; $j.token_secret
for /f "usebackq delims=" %%T in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\extract_token.ps1"`) do set "TOKEN_SECRET=%%T"
del "%TEMP%\pat_result.txt" >nul 2>nul
del "%TEMP%\extract_token.ps1" >nul 2>nul

if "!TOKEN_SECRET!"=="" (
    echo [ERROR] トークンの抽出に失敗しました。
    set "SNOWFLAKE_PASSWORD="
    exit /b 1
)

if not exist "!SANDBOX_HOME!\.snowflake" mkdir "!SANDBOX_HOME!\.snowflake"

(
echo default_connection_name = "handson"
echo.
echo [connections.handson]
echo account = "!SF_ACCOUNT!"
echo user = "!SF_USER!"
echo password = "!TOKEN_SECRET!"
echo role = "ACCOUNTADMIN"
echo warehouse = "COMPUTE_WH"
) > "!CONFIG_FILE!"

set "SNOWFLAKE_PASSWORD="
echo --- PAT 生成完了。接続設定を作成しました ---
exit /b 0

REM =============================================================================
REM cortex 起動
REM =============================================================================
:launch_cortex
echo --- CoCo CLI を起動します ---
echo     アプリの画面を見るには、別のウィンドウで start_dev_win.bat を実行してください。
echo.
set "USERPROFILE=!SANDBOX_HOME!"
set "HOME=!SANDBOX_HOME!"
set "SNOWFLAKE_HOME=!SANDBOX_HOME!\.snowflake"

cortex -c handson -w "!SANDBOX_HOME!" --setting-sources project --no-mcp --no-auto-update

echo.
echo cortex セッションを終了しました。
goto :eof
