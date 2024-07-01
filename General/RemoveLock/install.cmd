@echo off
REM Run the PowerShell script
Powershell.exe -ExecutionPolicy Bypass -File "%TargetDir%\RemoveLock.ps1"

if %ERRORLEVEL% EQU 0 (
    echo Script ran successfully
    REM Create or update the file used for detection rules directly in the C: drive
    echo %DATE% %TIME% > "C:\LastRun.txt"
) else (
    echo Script failed to run
)

REM Exit
exit /b 0