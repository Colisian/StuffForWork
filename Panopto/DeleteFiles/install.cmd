@echo off
copy ".\cleanPanoptoRecorder.ps1" "%C:\PerfLogs\CleanPanoptoRecorder.ps1" 
PowerShell.exe -ExecutionPolicy Bypass -File ".\ScheduleClean.ps1" 
