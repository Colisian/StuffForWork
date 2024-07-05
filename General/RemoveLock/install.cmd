@echo off

REM Ensure the Scripts directory exists
if not exist "C:\Program Files\Scripts" (
    mkdir "C:\Program Files\Scripts"
)

REM Copy the PowerShell scripts to the Scripts directory
copy "RemoveLock.ps1" "C:\Program Files\Scripts\RemoveLock.ps1"
copy "RemoveLockTask.ps1" "C:\Program Files\Scripts\RemoveLockTask.ps1"


REM Run the PowerShell script for the scheduled task
Powershell.exe -ExecutionPolicy Bypass -File "RemoveLockTask.ps1"

if %ERRORLEVEL% EQU 0 (
    echo Script ran successfully
    REM Create or update the file used for detection rules directly in the C: drive
    echo %DATE% %TIME% > "C:\PerfLogs\LastRun.txt"
) else (
    echo Script failed to run
)

REM Exit
exit /b 0