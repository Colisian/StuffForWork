@echo off
PowerShell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0PythonPath.ps1"
exit /b %ERRORLEVEL%