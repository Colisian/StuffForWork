@echo off

:: Ensure the script runs as Administrator
if not "%1"=="elevated" (
    powershell -Command "Start-Process cmd -ArgumentList '/c %~0 elevated' -Verb RunAs"
    exit /b
)

:: Run the PowerShell script
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0oclcdeploy.ps1"

:: Exit with success
exit /b 0
