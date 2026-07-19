# Uninstall-IdleLogoff.ps1
#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'
$TaskName  = 'LabIdleLogoff'
$ScriptDir = 'C:\ProgramData\LabIdleLogoff'

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false

# Kill any running watcher instances launched by the task
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*Watch-Idle.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Remove-Item -Path $ScriptDir -Recurse -Force
exit 0