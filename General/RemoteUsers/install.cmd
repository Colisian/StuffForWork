@echo off
setlocal enabledelayedexpansion

REM Log the execution context for troubleshooting
echo %DATE% %TIME% - Install started >> C:\PerfLogs\IntuneInstall_Debug.log
echo Current Directory: %CD% >> C:\PerfLogs\IntuneInstall_Debug.log
echo Script Directory (dp0): %~dp0 >> C:\PerfLogs\IntuneInstall_Debug.log
echo Full Script Path: %~f0 >> C:\PerfLogs\IntuneInstall_Debug.log

REM Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"

REM Remove trailing backslash if present for consistency
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM Build the full path to the PowerShell script
set "PS_SCRIPT=%SCRIPT_DIR%\AddRemoteUser.ps1"

echo PowerShell Script Path: %PS_SCRIPT% >> C:\PerfLogs\IntuneInstall_Debug.log

REM Verify the PowerShell script exists
if not exist "%PS_SCRIPT%" (
    echo ERROR: PowerShell script not found at %PS_SCRIPT% >> C:\PerfLogs\IntuneInstall_Debug.log
    echo Script not found, listing directory contents: >> C:\PerfLogs\IntuneInstall_Debug.log
    dir "%SCRIPT_DIR%" >> C:\PerfLogs\IntuneInstall_Debug.log 2>&1
    exit /b 1
)

REM Create log directory if it doesn't exist
if not exist "C:\PerfLogs" mkdir "C:\PerfLogs"

REM Force 64-bit PowerShell execution (critical for System context)
REM Check if we're running in 32-bit context on 64-bit OS
if exist "%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe" (
    echo Using SysNative path for 64-bit PowerShell >> C:\PerfLogs\IntuneInstall_Debug.log
    "%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
) else (
    echo Using System32 path for PowerShell >> C:\PerfLogs\IntuneInstall_Debug.log
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
)

set "PS_EXIT=%ERRORLEVEL%"
echo PowerShell exit code: %PS_EXIT% >> C:\PerfLogs\IntuneInstall_Debug.log

endlocal & exit /b %PS_EXIT%