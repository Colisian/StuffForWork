
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -Command `"$path = 'C:\PanoptoRecorder'; $days = 2; Get-ChildItem -Path `$path -Recurse | Where-Object { `$_.LastWriteTime -lt (Get-Date).AddDays(-`$days) -and `$_.FullName -notmatch 'C:\\PanoptoRecorder\\eventLogs' -and `$_.FullName -notmatch 'C:\\PanoptoRecorder\\UCSUploads' } | Remove-Item -Force -Recurse -Confirm:`$false`""

# Set the trigger for the scheduled task to weekly on Sundays at 3 AM
$Trigger = New-ScheduledTaskTrigger -Daily -At 2am

# Configure settings for the scheduled task (e.g., allow the task to run on batteries)
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

# define the user account under which the task runs, using SYSTEM for highest privileges
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

#Create task
Register-ScheduledTask -TaskName "ClearPanoptoRecorderFiles" -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal

