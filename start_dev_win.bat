@echo off
chcp 65001 >nul

REM =============================================================================
REM start_dev_win.bat  (Windows 用 - アプリを手元で起動して画面を確認する)
REM =============================================================================
REM setup_win.bat で作った接続設定（.snowflake\config.toml）を使って、
REM app\ の Next.js アプリを http://localhost:3000 で起動します。
REM CoCo CLI がファイルを書き換えると、ブラウザの画面が自動で更新されます。
REM 止めるときは、このウィンドウで Ctrl + C を押してください。

if "%DEV_GUARD%"=="1" goto :main

set "DEV_GUARD=1"
cmd /k "%~f0"
exit /b

:main
setlocal enabledelayedexpansion

cd /d "%~dp0"
set "SANDBOX_HOME=%~dp0"
if "!SANDBOX_HOME:~-1!"=="\" set "SANDBOX_HOME=!SANDBOX_HOME:~0,-1!"

if not exist "!SANDBOX_HOME!\.snowflake\config.toml" (
    echo [ERROR] 接続設定がありません。先に setup_win.bat を実行してください。
    goto :eof
)

set "SNOWFLAKE_HOME=!SANDBOX_HOME!\.snowflake"
cd /d "!SANDBOX_HOME!\app"

if not exist "node_modules" (
    echo --- 初回のみ: アプリの部品をインストールしています ^(npm install、1〜3 分^) ---
    call npm install
    if errorlevel 1 (
        echo [ERROR] npm install に失敗しました。社内プロキシなどで registry.npmjs.org に接続できない可能性があります。
        goto :eof
    )
)

echo.
echo ============================================================
echo  アプリを起動します: http://localhost:3000
echo  止めるときは Ctrl + C
echo ============================================================
echo.
start "" "http://localhost:3000"
call npm run dev
