@echo off
setlocal

REM Force the 64-bit PowerShell host so the sentinel under HKLM\SOFTWARE is
REM found and removed rather than missed under Wow6432Node.
set PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe

set SCRIPT=%~dp0Uninstall-DefaultPrinter.ps1

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set EC=%ERRORLEVEL%

echo Uninstall-DefaultPrinter.ps1 exited with %EC%
exit /b %EC%
