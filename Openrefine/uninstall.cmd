@echo off
start /wait "" "Program Files(x86)\OpenRefine\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES /ALLUSERS /NORESTART
exit /b %errorlevel%