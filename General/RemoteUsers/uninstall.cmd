@echo off
REM Force 64-bit PowerShell to avoid WOW64 redirection issues
%SystemRoot%\System32\WindowsPowerShell\v1.0\PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RemoveRemoteUser.ps1"
exit /b %ERRORLEVEL%