:: Microsoft Access Database Engine 2010 {90140000-00D1-0409-1000-0000000FF1CE}
:: OCLC Connexion client {106AE75F-9EFC-4721-BB06-DB6683EB8DA9}

@echo off
:: Uninstall OCLC Connexion client
msiexec.exe /x {106AE75F-9EFC-4721-BB06-DB6683EB8DA9} /qn /norestart
if %errorlevel% neq 0 (
   echo Failed to uninstall Connexion Client. Exiting...
   exit /b 1 
)

msiexec.exe /x "{0DD5834E-651D-4DAD-AC56-5340BEF5DDDD}" /qn /norestart
if %errorlevel% neq 0 (
   echo Failed to uninstall Connexion Client. Exiting...
   exit /b 1
)

:: Uninstall Microsoft Access Database Engine 2010
msiexec.exe /x {90140000-00D1-0409-1000-0000000FF1CE} /qn /norestart
if %errorlevel% neq 0 (
    echo Failed to uninstall Access Database Engine. Exiting...
   exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstalloclcdir.ps1"

echo Uninstall complete
exit /b 0