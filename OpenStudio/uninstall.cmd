@echo off
REM 1) Remove the application folder
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Remove-Item 'C:\Program Files\OpenStudio' -Recurse -Force"

REM 2) Remove the desktop shortcut (if it exists)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "if (Test-Path 'C:\Users\Public\Desktop\OpenStudio.lnk') { Remove-Item 'C:\Users\Public\Desktop\OpenStudio.lnk' -Force }"

exit /b %errorlevel%
