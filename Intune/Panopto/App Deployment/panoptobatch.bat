@echo off
REM  Install the Panopto Recorder 

msiexec /i "panoptorecorder.msi" /qn /l*v "C:\PerfLogs\panoptoInstall.log" PANOPTO_SERVER=umd.hosted.panopto.com

REM check if installation was successfull
if %ERRORLEVEL% equ 0 (
   REM Apply registry changes
   reg add "HKLM\SOFTWARE\Panopto\Panopto Recorder" /v WRDeleteWhenUploadComplete /t REG_SZ /d "True" /f
   echo Regristry changes applied
) else (
   echo Failed to install Panopto Recorder
)
