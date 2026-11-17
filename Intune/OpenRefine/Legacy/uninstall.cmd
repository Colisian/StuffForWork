@echo off
start /wait "" "C:\Program Files (x86)\OpenRefine\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES /ALLUSERS /NORESTART
exit /b %errorlevel%