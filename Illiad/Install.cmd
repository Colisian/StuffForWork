@echo off
REM Install the Illiad Client MSI
msiexec /i "%~dp0ILLiadClientSetup.msi" /qn /norestart
echo Illiad Client Installed

REM Run Powershell script to hide shortcuts
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Hide-Shortcuts.ps1"
echo Shortcut cleanup completed 

exit /b 0