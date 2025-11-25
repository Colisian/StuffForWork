@echo off
REM =========================================
REM SysAid Agent - Intune Silent Installer
REM =========================================

REM Install SysAid Agent using MSI + MST
echo Installing SysAid Agent...
msiexec /i "%~dp0SysAidAgent.msi" /qn TRANSFORMS="%~dp0SysAidAgentx64.mst" /norestart /L*V "%TEMP%\SysAidAgent_Install.log"

if %errorlevel% neq 0 (
    echo MSI installation failed with error code %errorlevel%
    exit /b %errorlevel%
)

REM Run post-install configuration
echo Running post-install configuration...
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Configure-SysAid.ps1"

exit /b %errorlevel%