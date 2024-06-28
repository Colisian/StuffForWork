@echo off
set TargetDir=C:\IntuneApp

if not exist "%TargetDir%" (
   mkdir "%TargetDir%"
)

copy "%~dp0DisableLockOption.ps1" "%TARGET_DIR%\"

Powershell.exe -ExecutionPolicy Bypass -File "%TargetDir%\RemoveLock.ps1"

