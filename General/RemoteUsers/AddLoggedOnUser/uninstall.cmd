@echo off
setlocal enabledelayedexpansion

REM Create log directory BEFORE the first write, or early logging is lost
if not exist "C:\ProgramData\RemoteUsers" mkdir "C:\ProgramData\RemoteUsers"
set "LOG=C:\ProgramData\RemoteUsers\AddLoggedOnUser_Uninstall_Debug.log"

REM Log the execution context for troubleshooting
echo %DATE% %TIME% - Uninstall started >> "%LOG%"
echo Current Directory: %CD% >> "%LOG%"
echo Script Directory (dp0): %~dp0 >> "%LOG%"

REM Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"

REM Remove trailing backslash if present for consistency
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM Build the full path to the PowerShell script
set "PS_SCRIPT=%SCRIPT_DIR%\RemoveLoggedOnUser.ps1"

echo PowerShell Script Path: %PS_SCRIPT% >> "%LOG%"

REM Verify the PowerShell script exists
if not exist "%PS_SCRIPT%" (
    echo ERROR: PowerShell script not found at %PS_SCRIPT% >> "%LOG%"
    exit /b 1
)

REM Force 64-bit PowerShell execution
if exist "%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe" (
    echo Using SysNative path for 64-bit PowerShell >> "%LOG%"
    "%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
) else (
    echo Using System32 path for PowerShell >> "%LOG%"
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
)

set "PS_EXIT=%ERRORLEVEL%"
echo PowerShell exit code: %PS_EXIT% >> "%LOG%"

endlocal & exit /b %PS_EXIT%
