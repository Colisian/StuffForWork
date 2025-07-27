@echo off
start /wait "" "%~dp0AutoHotkey.exe" /Silent /Uninstall

exit /b %errorlevel%