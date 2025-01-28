@echo off
start /wait "" "%~dp0Anaconda3-2024.10-1-Windows-x86_64.exe" /InstallationType=AllUsers /AddToPath=1 /RegisterPython=1 /S /D=C:\ProgramData\Anaconda3
exit /b %errorlevel%

