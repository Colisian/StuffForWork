@echo off
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0InstallFonts.ps1"
exit /b %ERRORLEVEL%