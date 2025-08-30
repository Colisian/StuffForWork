

$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File 'C:\PerfLogs\CleanPanoptoRecorder.ps1'"

# Set the trigger for the scheduled task to weekly on Sundays at 3 AM
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am

# Configure settings for the scheduled task (e.g., allow the task to run on batteries)
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

# define the user account under which the task runs, using SYSTEM for highest privileges
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

#Create task
Register-ScheduledTask -TaskName "ClearPanoptoRecorderFiles" -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal

