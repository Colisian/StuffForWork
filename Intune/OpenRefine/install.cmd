@echo off
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Install-OpenRefine.ps1"
exit /b %errorlevel%
