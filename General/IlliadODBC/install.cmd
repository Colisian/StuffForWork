@echo off
:: install.cmd - Creates desktop shortcut for ILLiad ODBC Setup
:: This creates a shortcut that runs the PowerShell script with a hidden window

setlocal enabledelayedexpansion

echo.
echo ========================================
echo  ILLiad ODBC Setup - Shortcut Installer
echo ========================================
echo.

:: Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%Deploy-IlliadODBC.ps1"

:: Verify PowerShell script exists
if not exist "%PS_SCRIPT%" (
    echo ERROR: Deploy-IlliadODBC.ps1 not found in current directory!
    echo Expected: %PS_SCRIPT%
    echo.
    pause
    exit /b 1
)

:: Get user's desktop path from registry
for /f "usebackq tokens=3*" %%A in (`reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" /v Desktop 2^>nul`) do (
    set "DESKTOP=%%B"
)

:: Expand environment variables in desktop path
call set "DESKTOP=%DESKTOP%"

if "%DESKTOP%"=="" (
    echo ERROR: Could not determine desktop location
    echo.
    pause
    exit /b 1
)

echo Desktop location: %DESKTOP%
echo.

:: Create VBScript to generate the shortcut
set "VBS=%TEMP%\CreateILLiadShortcut_%RANDOM%.vbs"
set "SHORTCUT_NAME=ILLiad ODBC Setup.lnk"

(
    echo Set oWS = WScript.CreateObject^("WScript.Shell"^)
    echo sLinkFile = "%DESKTOP%\%SHORTCUT_NAME%"
    echo Set oLink = oWS.CreateShortcut^(sLinkFile^)
    echo oLink.TargetPath = "powershell.exe"
    echo oLink.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File ""%PS_SCRIPT%"""
    echo oLink.WorkingDirectory = "%SCRIPT_DIR%"
    echo oLink.Description = "ILLiad ODBC Database Connection Setup"
    echo oLink.IconLocation = "%%SystemRoot%%\System32\odbcad32.exe,0"
    echo oLink.Save
) > "%VBS%"

:: Run VBScript to create shortcut
echo Creating desktop shortcut...
cscript //nologo "%VBS%"

if errorlevel 1 (
    echo ERROR: Failed to create shortcut
    del "%VBS%" 2>nul
    pause
    exit /b 1
)

:: Cleanup
del "%VBS%" 2>nul

echo.
echo ========================================
echo  Installation Complete!
echo ========================================
echo.
echo Desktop shortcut created successfully:
echo   %DESKTOP%\%SHORTCUT_NAME%
echo.
echo Users can double-click the shortcut to
echo configure their ILLiad ODBC connection.
echo.
pause
