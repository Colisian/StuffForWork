

$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File 'C:\PerfLogs\CleanPanoptoRecorder.ps1'"
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "ClearPanoptoRecorderFiles" -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal

