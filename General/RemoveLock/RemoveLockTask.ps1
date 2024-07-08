#Setting the execution policy to bypass
Set-ExecutionPolicy RemoteSigned -Scope Process -Force

$taskname = "Disable Lock Workstation"
$scriptPath = "C:\Program Files\Scripts\RemoveLock.ps1"
$trigger = New-ScheduledTaskTrigger -AtLogOn
$action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

try {
    Register-ScheduledTask -TaskName $taskname -Action $action -Trigger $trigger -Settings $settings -Principal $principal
} catch {
    Write-Output "Error registering scheduled task: $_"
}

