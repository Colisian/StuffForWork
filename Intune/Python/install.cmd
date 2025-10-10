@echo off
PowerShell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Add-Python-To-Path.ps1"
exit /b %ERRORLEVEL%