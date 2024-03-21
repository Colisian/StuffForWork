@echo off
REM Check if the LastRun.txt file exists, create it if it doesn't
if not exist "C:\LastRun.txt" echo Created on %DATE% %TIME% > "C:\PerfLogs\LastRun.txt"

REM Run the PowerShell script
PowerShell.exe -ExecutionPolicy Bypass -File ".\ScheduleAndDeletePanoptoRec.ps1"

REM Check if the PowerShell script ran successfully
if %ERRORLEVEL% -eq 0 (
    echo Script ran successfully
    REM Create or update the file used for detection rules
    echo %DATE% %TIME% > "C:\PerfLogs\LastRun.txt"
) else (
    echo Script failed to run
)

REM Exit
exit /b 0
