@echo off
REM Install the Illiad Client MSI
msiexec /i "%~dp0AeonClientInstaller_6.0.6.0.msi" /qn /norestart ALLUSERS=1
echo Aeon Client Installed

REM Run Powershell script to hide shortcuts
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Aeon-HideShortcuts.ps1"
echo Shortcut cleanup completed 

exit /b 0