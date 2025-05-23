
@echo off
REM This command runs the PowerShell script with administrative privileges.
Powershell.exe -ExecutionPolicy Bypass -File "SetDomain.ps1" 
Powershell.exe -ExecutionPolicy Bypass -File "BlockGP.ps1" 

exit /B 0