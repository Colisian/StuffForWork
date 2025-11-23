@echo off
REM Install UMD Libraries Network Drive Mapper

REM Create the script directory
if not exist "C:\ProgramData\UMDLibraries\Scripts\" mkdir "C:\ProgramData\UMDLibraries\Scripts\"

REM Copy the PowerShell script
copy /Y "%~dp0DriveMapper.ps1" "C:\ProgramData\UMDLibraries\Scripts\DriveMapper.ps1"

REM Create shortcut on Public Desktop (all users)
powershell.exe -ExecutionPolicy Bypass -Command ^
"$WshShell = New-Object -ComObject WScript.Shell; ^
$Shortcut = $WshShell.CreateShortcut('%PUBLIC%\Desktop\Map Network Drives.lnk'); ^
$Shortcut.TargetPath = 'powershell.exe'; ^
$Shortcut.Arguments = '-ExecutionPolicy Bypass -NoProfile -WindowStyle Normal -File \"C:\ProgramData\UMDLibraries\Scripts\DriveMapper.ps1\"'; ^
$Shortcut.IconLocation = 'shell32.dll,275'; ^
$Shortcut.Description = 'Map UMD Libraries Network Drives'; ^
$Shortcut.WorkingDirectory = 'C:\ProgramData\UMDLibraries\Scripts'; ^
$Shortcut.Save()"

REM Create a registry key for detection
reg add "HKLM\SOFTWARE\UMDLibraries\NetworkDriveMapper" /v "Version" /t REG_SZ /d "1.0" /f

exit /b 0