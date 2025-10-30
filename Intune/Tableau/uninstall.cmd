@echo off
REM ----------------------------------------
REM Uninstall script for Tableau Public Desktop
REM ----------------------------------------

REM Define variables
SET "InstallerName=TableauPublicDesktop.exe"
SET "LogPath=C:\Logs\TableauPublic_uninstall.log"

REM Run uninstall silently
"%~dp0%InstallerName%" /uninstall /quiet /norestart /log "%LogPath%"

REM Check exit code
IF %ERRORLEVEL% EQU 0 (
    echo Uninstallation succeeded.
) ELSE (
    echo Uninstallation failed with error code %ERRORLEVEL%.
    exit /b %ERRORLEVEL%
)
