@echo off
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-Fonts.ps1"
exit /b %ERRORLEVEL%
