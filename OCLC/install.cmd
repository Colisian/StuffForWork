@echo off

:: Run the PowerShell script
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0oclcdeploy.ps1"

:: Exit with success
exit /b 0
