@echo off
setlocal

REM Force the 64-bit PowerShell host. Intune's agent may launch this wrapper
REM 32-bit, which would send HKLM\SOFTWARE writes into Wow6432Node.
set PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe

set SCRIPT=%~dp0Install-DefaultPrinter.ps1

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set EC=%ERRORLEVEL%

echo Install-DefaultPrinter.ps1 exited with %EC%
exit /b %EC%
