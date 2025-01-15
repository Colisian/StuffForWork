:: Microsoft Access Database Engine 2010 {90140000-00D1-0409-1000-0000000FF1CE}
:: OCLC Connexion client {106AE75F-9EFC-4721-BB06-DB6683EB8DA9}

@echo off
:: Uninstall OCLC Connexion client
msiexec /x {106AE75F-9EFC-4721-BB06-DB6683EB8DA9} /qn /norestart
if %errorlevel% neq 0 (
   exit /b 1 
)

:: Uninstall Microsoft Access Database Engine 2010
msiexec /x {90140000-00D1-0409-1000-0000000FF1CE} /qn /norestart
if %errorlevel% neq 0 (
   exit /b 1
)

echo Uninstall complete
exit /b 0