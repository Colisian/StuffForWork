@echo off
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Uninstall-OpenRefine.ps1"
exit /b %errorlevel%
