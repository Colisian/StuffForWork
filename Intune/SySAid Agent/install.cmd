@echo off
REM =========================================
REM SysAid Agent - Intune Silent Installer
REM =========================================
setlocal

@echo off
:: Install SysAid Agent using MSI + MST
msiexec /i "%~dp0SysAidAgent.msi" /qn TRANSFORMS="%~dp0SysAidAgentx64.mst" /norestart

:: Run post-install configuration
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Configure-SysAid.ps1"

exit /b %errorlevel%