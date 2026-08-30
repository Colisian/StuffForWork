@echo off
setlocal
set "PowerShellExe=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PowerShellExe=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PowerShellExe%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Uninstall-LibrarySignInBackground.ps1"
exit /b %errorlevel%
