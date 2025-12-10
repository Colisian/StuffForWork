@echo off
setlocal enabledelayedexpansion

REM Log the execution context for troubleshooting
echo %DATE% %TIME% - Uninstall started >> C:\PerfLogs\IntuneUninstall_Debug.log
echo Current Directory: %CD% >> C:\PerfLogs\IntuneUninstall_Debug.log
echo Script Directory (dp0): %~dp0 >> C:\PerfLogs\IntuneUninstall_Debug.log

REM Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"

REM Remove trailing backslash if present for consistency
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM Build the full path to the PowerShell script
set "PS_SCRIPT=%SCRIPT_DIR%\RemoveRemoteUser.ps1"

echo PowerShell Script Path: %PS_SCRIPT% >> C:\PerfLogs\IntuneUninstall_Debug.log

REM Verify the PowerShell script exists
if not exist "%PS_SCRIPT%" (
    echo ERROR: PowerShell script not found at %PS_SCRIPT% >> C:\PerfLogs\IntuneUninstall_Debug.log
    exit /b 1
)

REM Create log directory if it doesn't exist
if not exist "C:\PerfLogs" mkdir "C:\PerfLogs"

REM Force 64-bit PowerShell execution
if exist "%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe" (
    echo Using SysNative path for 64-bit PowerShell >> C:\PerfLogs\IntuneUninstall_Debug.log
    "%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
) else (
    echo Using System32 path for PowerShell >> C:\PerfLogs\IntuneUninstall_Debug.log
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
)

set "PS_EXIT=%ERRORLEVEL%"
echo PowerShell exit code: %PS_EXIT% >> C:\PerfLogs\IntuneUninstall_Debug.log

endlocal & exit /b %PS_EXIT%