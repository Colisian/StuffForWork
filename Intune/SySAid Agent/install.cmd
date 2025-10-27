@echo off
REM =========================================
REM SysAid Agent - Intune Silent Installer
REM =========================================
setlocal

REM Install SysAid Agent silently with Org parameters
msiexec /i "%~dp0SysAidAgent.msi" /qn /norestart ^
    ACCOUNT="umlibraryitd" ^
    SERVERURL="https://ticketing.lib.umd.edu" ^
    SERIAL="ENTER-YOUR-SERIAL-HERE"

:: Run post-install configuration script
powershell.exe -ExecutionPolicy Bypass -File "%~dp0SysAidAgentFirewall.ps1"

exit /b 0
