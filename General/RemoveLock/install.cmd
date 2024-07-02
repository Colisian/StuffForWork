@echo off

REM Ensure the Scripts directory exists
if not exist "C:\Scripts" (
    mkdir "C:\Scripts"
)

REM Copy the PowerShell scripts to the Scripts directory
copy "RemoveLock.ps1" "C:\Scripts\RemoveLock.ps1"
copy "RemoveLockTask.ps1" "C:\Scripts\RemoveLockTask.ps1"

copy "RemoveLock.ps1" "C:\PerfLogs\RemoveLock.ps1"

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