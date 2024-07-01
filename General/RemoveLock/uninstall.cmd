
@echo off
REM Run the PowerShell script to remove the DisableLockWorkstation registry entry
PowerShell.exe -ExecutionPolicy Bypass -File "UninstallRemoveLock.ps1"

REM Check if the PowerShell script ran successfully
if %ERRORLEVEL% EQU 0 (
    echo Script ran successfully
    REM Remove the detection file if it exists
    if exist "C:\PerfLogs\LastRun.txt" (
        del "C:\PerfLogs\LastRun.txt"
        echo Detection file removed.
    )
) else (
    echo Script failed to run
)

REM Exit
exit /b 0
