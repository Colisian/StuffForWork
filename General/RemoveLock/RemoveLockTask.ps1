$taskname = "Disable Lock Workstation"
$action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-ExecutionPolicy" Bypass -File C:\Script\RemoveLock.ps1
$trigger = New-ScheduleTaskTrigger -AtLogOn
$principle = New-ScheduledTaskPrincipal -UserId "NT Authority\Interactive" -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName $taskname -Action $action -Trigger $trigger -Principal $principle
