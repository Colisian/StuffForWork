#Define destination directory
$targetDir = "C:\Program Files\DiskSpaceMonitor"

#Make sure directory exits or create it
if (-not (Test-Path $targetDir)) {
    New-Item -Path $targetDir -ItemType Directory
}

#Copy the EmailMessage.ps1 script to the destination directory (relative to the location where the package is unpacked)
$sourceScript = ".\EmailMessage.ps1"

#Define destination path
$destinationPath = Join-Path -Path $targetDir -ChildPath "EmailMessage.ps1"

#Copy script to the target directory
Copy-Item -Path $sourceScript -Destination $destinationPath -Force 


#Task variables 
$scriptPath = $destinationPath
$taskName = "Disk Space Monitor"
$taskDescription = "Task to monitor disk space and send an email if it falls below a certain threshold"
# Creating a new daily task trigger
$trigger = New-ScheduledTaskTrigger -Daily -At "3:00 AM"
# Creating a new action to run the script
$action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-File `"$scriptPath`""

# Registering the scheduled task
Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Trigger $trigger -Action $action -RunLevel Highest -User "SYSTEM" -Force