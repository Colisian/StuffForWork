@echo off
PowerShell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Remove-Python-From-Path.ps1"
exit /b %ERRORLEVEL%