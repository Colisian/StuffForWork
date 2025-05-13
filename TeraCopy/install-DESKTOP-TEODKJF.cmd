echo off
start /wait "" "%~dp0teracopy.exe" /exenoui /quiet /norestart

exit /b %errorlevel%
