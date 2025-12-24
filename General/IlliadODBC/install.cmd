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
    exit /b 1
)

:: Use Public Desktop for all users (SYSTEM context deployment)
set "DESKTOP=%PUBLIC%\Desktop"

:: Verify Public Desktop folder exists
if not exist "%DESKTOP%" (
    echo ERROR: Public Desktop folder does not exist: %DESKTOP%
    echo Attempting to create it...
    mkdir "%DESKTOP%"
    if errorlevel 1 (
        echo ERROR: Failed to create Public Desktop folder
        echo.
        exit /b 1
    )
)

echo Desktop location: %DESKTOP%
echo.

:: Copy PowerShell script to permanent location
:: (Intune may clean up temp cache after installation)
set "INSTALL_DIR=C:\ProgramData\UMDLibraries\scripts"
set "PERMANENT_SCRIPT=%INSTALL_DIR%\Deploy-IlliadODBC.ps1"

echo Ensuring installation directory exists...
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
    if errorlevel 1 (
        echo ERROR: Failed to create directory: %INSTALL_DIR%
        echo.
        exit /b 1
    )
    echo   Created directory: %INSTALL_DIR%
) else (
    echo   Directory already exists: %INSTALL_DIR%
)

echo Copying PowerShell script to permanent location...
echo From: %PS_SCRIPT%
echo To:   %PERMANENT_SCRIPT%
copy /Y "%PS_SCRIPT%" "%PERMANENT_SCRIPT%" >nul
if errorlevel 1 (
    echo ERROR: Failed to copy PowerShell script
    echo.
    exit /b 1
)
echo.

:: Create VBScript to generate the shortcut
set "VBS=%TEMP%\CreateILLiadShortcut_%RANDOM%.vbs"
set "SHORTCUT_NAME=ILLiad ODBC Setup.lnk"

(
    echo Set oWS = WScript.CreateObject^("WScript.Shell"^)
    echo sLinkFile = "%DESKTOP%\%SHORTCUT_NAME%"
    echo Set oLink = oWS.CreateShortcut^(sLinkFile^)
    echo oLink.TargetPath = "powershell.exe"
    echo oLink.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File ""%PERMANENT_SCRIPT%"""
    echo oLink.WorkingDirectory = "%INSTALL_DIR%"
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
echo Installation directory:
echo   %INSTALL_DIR%
echo.
echo Users can double-click the shortcut to
echo configure their ILLiad ODBC connection.
echo.
exit /b 0
