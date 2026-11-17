@echo off
start /wait "" "%~dp0openrefine.exe" /VERYSILENT /LANG=english /NORESTART /AllUSERS

exit /b %errorlevel%