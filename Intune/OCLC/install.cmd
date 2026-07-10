@echo off
:: OCLC Connexion - Intune Win32 install wrapper
:: Uses the 64-bit PowerShell host via sysnative when launched from a 32-bit
:: process (Intune Management Extension); falls back to PATH otherwise.

set "PS=powershell.exe"
if exist "%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0oclcdeploy.ps1"

:: Propagate the script's exit code to Intune (0 = success, 3010 = soft reboot)
exit /b %errorlevel%
