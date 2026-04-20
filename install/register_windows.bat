@echo off
REM ============================================================
REM  IP Change Notifier — Windows Startup Registration
REM ============================================================
REM  This script registers ip_notifier.py as a Task Scheduler
REM  task that runs:
REM    1. At user logon
REM    2. On network availability (Event ID 10000)
REM
REM  Run this script once from an Administrator Command Prompt.
REM  To remove: schtasks /Delete /TN "IPChangeNotifier" /F
REM ============================================================

setlocal

set "SCRIPT_DIR=%~dp0.."
set "PYTHON_EXE=python"
set "TASK_NAME=IPChangeNotifier"
set "SCRIPT_PATH=%SCRIPT_DIR%\ip_notifier.py"

REM --- Verify the script exists ---
if not exist "%SCRIPT_PATH%" (
    echo ERROR: ip_notifier.py not found at %SCRIPT_PATH%
    echo Make sure you run this script from the install\ folder.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  Registering %TASK_NAME% in Task Scheduler...
echo ============================================================
echo.

REM --- Delete existing task if present ---
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo Removing existing task...
    schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
)

REM --- Create task triggered at user logon ---
schtasks /Create ^
    /TN "%TASK_NAME%" ^
    /TR "\"%PYTHON_EXE%\" \"%SCRIPT_PATH%\"" ^
    /SC ONLOGON ^
    /RL HIGHEST ^
    /F

if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Failed to create the scheduled task.
    echo Make sure you are running this as Administrator.
    pause
    exit /b 1
)

echo.
echo Task "%TASK_NAME%" registered successfully.
echo It will run at every user logon.
echo.
echo TIP: To also trigger on network changes, open Task Scheduler,
echo find "%TASK_NAME%", go to Triggers, and add:
echo   Begin the task: On an event
echo   Log:    Microsoft-Windows-NetworkProfile/Operational
echo   Source: NetworkProfile
echo   Event ID: 10000
echo.
echo Done!
pause
