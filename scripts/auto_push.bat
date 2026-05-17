@echo off
REM ============================================================
REM  auto_push.bat
REM
REM  Run after Cowork drops a new briefing into briefings/.
REM  Pulls server side commits (the GitHub Action regenerates
REM  index.html on push, so local main goes behind), regenerates
REM  index.html locally, stages, commits, pushes. Bails out
REM  cleanly if there is nothing to commit.
REM
REM  Schedule this in Windows Task Scheduler to run 30 minutes
REM  after each Cowork scheduled task fires.
REM ============================================================

setlocal enabledelayedexpansion

set REPO=C:\Users\VictoriaGeh\Documents\Github\corpdev-ai-briefing
set LOGFILE=%REPO%\scripts\auto_push.log

REM Timestamp for the log
for /f "tokens=2 delims==." %%a in ('wmic os get localdatetime /value 2^>nul ^| find "="') do set TS=%%a
if not defined TS for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm-ss"') do set TS=%%i

echo. >> "%LOGFILE%"
echo === Run at %TS% === >> "%LOGFILE%"

cd /d "%REPO%" || (echo cd failed >> "%LOGFILE%" & exit /b 1)

REM 1. Sync with any server side commits (e.g., the Action's index refresh)
git pull --rebase --autostash origin main >> "%LOGFILE%" 2>&1

REM 2. Regenerate the index from current briefings
python scripts\generate_index.py >> "%LOGFILE%" 2>&1

REM 3. Stage any new or modified briefings + the regenerated index
git add briefings index.html >> "%LOGFILE%" 2>&1

REM 4. Bail out cleanly if nothing changed
git diff --staged --quiet
if !errorlevel! equ 0 (
    echo No staged changes. Nothing to commit. >> "%LOGFILE%"
    exit /b 0
)

REM 5. Use today's date in the commit message
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set TODAY=%%i

git commit -m "briefing: !TODAY!" >> "%LOGFILE%" 2>&1
git push origin main >> "%LOGFILE%" 2>&1

echo Done. >> "%LOGFILE%"
endlocal
