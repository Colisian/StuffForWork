@echo off
setlocal

REM Vendor uninstaller (WARNING: likely removes Pharos Popup)
set UNINST="C:\Program Files (x86)\Pharos\Bin\Uninst.exe"
set ARGS=/s Popups

if exist %UNINST% (
  echo Running vendor uninstaller...
  %UNINST% %ARGS%
  set EC=%ERRORLEVEL%
) else (
  echo Uninstaller not found at %UNINST%
  set EC=0
)

REM Remove detection marker
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Remove-Item -LiteralPath 'C:\ProgramData\UMD\Pharos\MarylandRoom_x64.installed' -Force -ErrorAction SilentlyContinue"

echo Uninstall completed with %EC%
exit /b %EC%
