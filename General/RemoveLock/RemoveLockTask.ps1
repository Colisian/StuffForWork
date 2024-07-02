
$targetDirectory = "C:\Scripts"

# Ensure the target directory exists
if (-not (Test-Path $targetDirectory)) {
    New-Item -Path $targetDirectory -ItemType Directory
}

$sourceScript = ".\RemoveLock.ps1"
$destinationPath = Join-Path -Path $targetDirectory -ChildPath "RemoveLock.ps1"

Copy-Item - Path $sourceScript -Destination $destinationPath -Force


$scriptPath = "C:\PerfLogs\RemoveLock"

$taskname = "Disable Lock Workstation"
$scriptPath = $destinationPath
$trigger = New-ScheduledTaskTrigger -AtLogOn
$action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\INTERACTIVE" -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName $taskname -Action $action -Trigger $trigger -Settings $Settings  -Principal $principal
