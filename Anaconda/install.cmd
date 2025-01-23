@echo off
start /wait start /wait "" "%~dp0Anaconda3-<version>-Windows-x86_64.exe" /InstallationType=AllUsers /AddToPath=1 /RegisterPython=1 /S /D=C:\ProgramData\Anaconda3
exit /b %errorlevel%

