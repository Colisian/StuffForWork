@echo off
start /wait "" "%~dp0teracopy4rc.exe" /exenoui /noprereqs /qn

exit /b %errorlevel%
