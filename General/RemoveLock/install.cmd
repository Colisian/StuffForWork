@echo off

Rem Ensure Perf Logs folder exists

if not exist "C:\PerfLogs" (
   mkdir "C:\PerfLogs"
)

REM Run the PowerShell script
Powershell.exe -ExecutionPolicy Bypass -File "RemoveLock.ps1"

if %ERRORLEVEL% EQU 0 (
    echo Script ran successfully
    REM Create or update the file used for detection rules directly in the C: drive
    echo %DATE% %TIME% > "C:\PerfLogs\LastRun.txt"
) else (
    echo Script failed to run
)

REM Exit
exit /b 0