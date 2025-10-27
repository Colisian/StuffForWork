@echo off
REM ----------------------------------------
REM Install script for Tableau Public Desktop
REM ----------------------------------------

REM Define variables
SET "InstallerName=TableauPublicDesktop.exe"
SET "InstallPath=C:\Program Files\Tableau Public"
SET "LogPath=C:\Logs\TableauPublic_install.log"

REM Run installer silently, accept EULA and set properties
"%~dp0%InstallerName%" /quiet /norestart ACCEPTEULA=1 INSTALLDIR="%InstallPath%" AUTOUPDATE=1 SENDTELEMETRY=0 DESKTOPSHORTCUT=1 /log "%LogPath%"

REM Check exit code
IF %ERRORLEVEL% EQU 0 (
    echo Installation succeeded.
) ELSE (
    echo Installation failed with error code %ERRORLEVEL%.
    exit /b %ERRORLEVEL%
)
