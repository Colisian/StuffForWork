$taskname = "Disable Lock Workstation"
$action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-ExecutionPolicy" Bypass -File C:\PerfLogs\RemoveLock.ps1
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\INTERACTIVE" -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName $taskname -Action $action -Trigger $trigger -Principal $principal
