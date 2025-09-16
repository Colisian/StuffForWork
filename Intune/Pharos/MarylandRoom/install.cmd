@echo off
setlocal

REM Run the PowerShell installer script from the same folder as this CMD
set SCRIPT=%~dp0Install-MarylandRoom.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set EC=%ERRORLEVEL%

echo Install-MarylandRoom.ps1 exited with %EC%
exit /b %EC%
