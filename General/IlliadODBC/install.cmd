@echo off
:: install.cmd - Creates desktop shortcuts for ILLiad and Ares ODBC Setup
:: This creates shortcuts that run the PowerShell scripts with hidden windows

setlocal enabledelayedexpansion

echo.
echo =============================================
echo  Atlas ODBC Setup - Shortcut Installer
echo  (ILLiad and Ares)
echo =============================================
echo.

:: Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"
set "ILLIAD_SCRIPT=%SCRIPT_DIR%Deploy-IlliadODBC.ps1"
set "ARES_SCRIPT=%SCRIPT_DIR%Deploy-AresODBC.ps1"

:: Verify PowerShell scripts exist
set "MISSING_SCRIPTS=0"

if not exist "%ILLIAD_SCRIPT%" (
    echo ERROR: Deploy-IlliadODBC.ps1 not found!
    echo Expected: %ILLIAD_SCRIPT%
    set "MISSING_SCRIPTS=1"
)

if not exist "%ARES_SCRIPT%" (
    echo ERROR: Deploy-AresODBC.ps1 not found!
    echo Expected: %ARES_SCRIPT%
    set "MISSING_SCRIPTS=1"
)

if "%MISSING_SCRIPTS%"=="1" (
    echo.
    exit /b 1
)

echo Found both PowerShell scripts.
echo.

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

:: Copy PowerShell scripts to permanent location
:: (Intune may clean up temp cache after installation)
set "INSTALL_DIR=C:\ProgramData\UMDLibraries\scripts"
set "PERMANENT_ILLIAD=%INSTALL_DIR%\Deploy-IlliadODBC.ps1"
set "PERMANENT_ARES=%INSTALL_DIR%\Deploy-AresODBC.ps1"

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

echo.
echo Copying PowerShell scripts to permanent location...

echo   Copying ILLiad script...
copy /Y "%ILLIAD_SCRIPT%" "%PERMANENT_ILLIAD%" >nul
if errorlevel 1 (
    echo ERROR: Failed to copy ILLiad PowerShell script
    echo.
    exit /b 1
)

echo   Copying Ares script...
copy /Y "%ARES_SCRIPT%" "%PERMANENT_ARES%" >nul
if errorlevel 1 (
    echo ERROR: Failed to copy Ares PowerShell script
    echo.
    exit /b 1
)

echo   Scripts copied successfully.
echo.

:: Create VBScript to generate the ILLiad shortcut
set "VBS=%TEMP%\CreateODBCShortcut_%RANDOM%.vbs"
set "ILLIAD_SHORTCUT=ILLiad ODBC Setup.lnk"

echo Creating ILLiad desktop shortcut...
(
    echo Set oWS = WScript.CreateObject^("WScript.Shell"^)
    echo sLinkFile = "%DESKTOP%\%ILLIAD_SHORTCUT%"
    echo Set oLink = oWS.CreateShortcut^(sLinkFile^)
    echo oLink.TargetPath = "powershell.exe"
    echo oLink.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File ""%PERMANENT_ILLIAD%"""
    echo oLink.WorkingDirectory = "%INSTALL_DIR%"
    echo oLink.Description = "ILLiad ODBC Database Connection Setup"
    echo oLink.IconLocation = "%%SystemRoot%%\System32\odbcad32.exe,0"
    echo oLink.Save
) > "%VBS%"

cscript //nologo "%VBS%"
if errorlevel 1 (
    echo ERROR: Failed to create ILLiad shortcut
    del "%VBS%" 2>nul
    exit /b 1
)
del "%VBS%" 2>nul
echo   Created: %ILLIAD_SHORTCUT%

:: Create VBScript to generate the Ares shortcut
set "VBS=%TEMP%\CreateODBCShortcut_%RANDOM%.vbs"
set "ARES_SHORTCUT=Ares ODBC Setup.lnk"

echo Creating Ares desktop shortcut...
(
    echo Set oWS = WScript.CreateObject^("WScript.Shell"^)
    echo sLinkFile = "%DESKTOP%\%ARES_SHORTCUT%"
    echo Set oLink = oWS.CreateShortcut^(sLinkFile^)
    echo oLink.TargetPath = "powershell.exe"
    echo oLink.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File ""%PERMANENT_ARES%"""
    echo oLink.WorkingDirectory = "%INSTALL_DIR%"
    echo oLink.Description = "Ares ODBC Database Connection Setup"
    echo oLink.IconLocation = "%%SystemRoot%%\System32\odbcad32.exe,0"
    echo oLink.Save
) > "%VBS%"

cscript //nologo "%VBS%"
if errorlevel 1 (
    echo ERROR: Failed to create Ares shortcut
    del "%VBS%" 2>nul
    exit /b 1
)
del "%VBS%" 2>nul
echo   Created: %ARES_SHORTCUT%

echo.
echo =============================================
echo  Installation Complete!
echo =============================================
echo.
echo Desktop shortcuts created:
echo   - %DESKTOP%\%ILLIAD_SHORTCUT%
echo   - %DESKTOP%\%ARES_SHORTCUT%
echo.
echo Installation directory:
echo   %INSTALL_DIR%
echo.
echo Users can double-click the shortcuts to
echo configure their ODBC connections.
echo.
exit /b 0
