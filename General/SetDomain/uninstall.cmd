@echo off

REM Delete the DefaultDomainName registry key
REG DELETE "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v DefaultDomainName /f

REM Re-enable GlobalProtect VPN as a Sign-In Option by deleting the 'Disabled' value
REG DELETE "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{25CA8579-1BD8-469c-B9FC-6AC45A161C18}\" /v Disabled /f

REM Log the uninstallation
set logFolder=C:\Scripts
set logFile=%logFolder%\ScriptExecutionLog.txt
if not exist %logFolder% mkdir %logFolder%
echo Uninstall script executed on: %date% %time% >> %logFile%
echo GlobalProtect sign-in option re-enabled. >> %logFile%
echo DefaultDomainName registry key removed. >> %logFile%

exit /B 0