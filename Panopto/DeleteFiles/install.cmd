@echo off
copy ".\CleanPanoptoRecorder.ps1" "C:\PerfLogs\CleanPanoptoRecorder.ps1" 
PowerShell.exe -ExecutionPolicy Bypass -File ".\ScheduleClean.ps1" 
