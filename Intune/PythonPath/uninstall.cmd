@echo off
PowerShell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0RemovePythonFromPath.ps1"
exit /b %ERRORLEVEL%