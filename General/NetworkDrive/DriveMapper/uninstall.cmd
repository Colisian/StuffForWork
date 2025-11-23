@echo off
REM Uninstall UMD Libraries Network Drive Mapper

REM Remove the shortcut
del /F /Q "%PUBLIC%\Desktop\Map Network Drives.lnk" 2>nul

REM Remove the script
del /F /Q "C:\ProgramData\UMDLibraries\Scripts\DriveMapper.ps1" 2>nul
rmdir "C:\ProgramData\UMDLibraries\Scripts\" 2>nul
rmdir "C:\ProgramData\UMDLibraries\" 2>nul

REM Remove registry key
reg delete "HKLM\SOFTWARE\UMDLibraries\NetworkDriveMapper" /f 2>nul

exit /b 0
```
