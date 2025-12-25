@echo off
REM Calls the PowerShell uninstall script with appropriate execution policy

PowerShell.exe -ExecutionPolicy Bypass -File "%~dp0Uninstall-IlliadODBC.ps1"
exit /b %errorlevel%
