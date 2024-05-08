
#Task variables 
$scriptPath = "C:\Users\cmcle\Documents\PowerShellScripts\General\EmailMessage.ps1"
$taskName = "Disk Space Monitor"
$taskDescription = "Task to monitor disk space and send an email if it falls below a certain threshold"
$triggerTime = New-TimeSpan -Hours 24

# Creating a new daily task trigger
$trigger = New-ScheduledTaskTrigger -Daily -At "3:00 AM"

# Creating a new action to run the script
$action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-File `"$scriptPath`""

# Registering the scheduled task
Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Trigger $trigger -Action $action -RunLevel Highest -User "SYSTEM" -Force