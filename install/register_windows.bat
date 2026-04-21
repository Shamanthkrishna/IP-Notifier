@echo off
REM ============================================================
REM  IP Change Notifier — Windows Task Scheduler Registration
REM ============================================================
REM  Registers ip_notifier.py as a scheduled task with triggers:
REM    1. At user logon
REM    2. On wake from sleep / hibernate  (30-second delay)
REM    3. On network profile connected    (10-second delay)
REM
REM  Run once from an Administrator Command Prompt.
REM  To remove: schtasks /Delete /TN "IPChangeNotifier" /F
REM ============================================================

setlocal

REM --- Self-elevate if not running as Administrator ---
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Requesting Administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs -Wait"
    exit /b
)

set "PS_SCRIPT=%~dp0register_windows.ps1"

if not exist "%PS_SCRIPT%" (
    echo ERROR: register_windows.ps1 not found at %PS_SCRIPT%
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Task registration failed. See output above.
    pause
    exit /b 1
)

pause
