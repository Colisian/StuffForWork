@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UninstallTeraCopy.ps1"
exit /b %errorlevel%
