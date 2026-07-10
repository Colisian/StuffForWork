@echo off
:: OCLC Connexion - Intune Win32 uninstall wrapper
:: Product codes:
::   OCLC Connexion client           {106AE75F-9EFC-4721-BB06-DB6683EB8DA9}
::   OCLC Connexion ComService       {0DD5834E-651D-4DAD-AC56-5340BEF5DDDD}
::   MS Access Database Engine 2010  {90140000-00D1-0409-1000-0000000FF1CE}
::
:: msiexec exit codes treated as success:
::   0 = removed, 1605 = product not installed (nothing to do), 3010 = removed + reboot required

if not exist "%ProgramData%\OCLC" mkdir "%ProgramData%\OCLC"

:: Uninstall OCLC Connexion client
msiexec.exe /x {106AE75F-9EFC-4721-BB06-DB6683EB8DA9} /qn /norestart /l*v "%ProgramData%\OCLC\Connexion_uninstall.log"
if %errorlevel% neq 0 if %errorlevel% neq 1605 if %errorlevel% neq 3010 (
    echo Failed to uninstall Connexion client - msiexec exit code %errorlevel%
    exit /b 1
)

:: Uninstall OCLC Connexion ComService
msiexec.exe /x {0DD5834E-651D-4DAD-AC56-5340BEF5DDDD} /qn /norestart /l*v "%ProgramData%\OCLC\ComService_uninstall.log"
if %errorlevel% neq 0 if %errorlevel% neq 1605 if %errorlevel% neq 3010 (
    echo Failed to uninstall Connexion ComService - msiexec exit code %errorlevel%
    exit /b 1
)

:: Remove the desktop shortcut and any leftover install directory
set "PS=powershell.exe"
if exist "%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstalloclcdir.ps1"

echo Uninstall complete
exit /b 0
