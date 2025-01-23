@echo off
start /wait "" "%~dp0BurnOut.exe" /uninstall {851D74A0-D029-4AC7-9CBE-E50455C24237}
exit /b %errorlevel%
