# Install-IdleLogoff.ps1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [int]$IdleLimitSeconds = 600,
    [int]$PollSeconds      = 15,
    [string]$Version       = '1.0.0'
)

$ErrorActionPreference = 'Stop'
$ScriptDir  = 'C:\ProgramData\LabIdleLogoff'
$Watcher    = Join-Path $ScriptDir 'Watch-Idle.ps1'
$VersionTag = Join-Path $ScriptDir 'version.txt'
$LogFile    = Join-Path $ScriptDir 'install.log'
$TaskName   = 'LabIdleLogoff'

New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null
Start-Transcript -Path $LogFile -Append | Out-Null

try {
    # --- Copy watcher payload from package into ProgramData ---
    $srcWatcher = Join-Path $PSScriptRoot 'Watch-Idle.ps1'
    Copy-Item -Path $srcWatcher -Destination $Watcher -Force

    # --- Register the per-user scheduled task ---
    $psExe   = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $args    = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Watcher`" -IdleLimit $IdleLimitSeconds -Poll $PollSeconds"

    $Action    = New-ScheduledTaskAction -Execute $psExe -Argument $args
    $Trigger   = New-ScheduledTaskTrigger -AtLogOn
    # BUILTIN\Users so it launches in each interactive patron's context
    $Principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
    $Settings  = New-ScheduledTaskSettingsSet `
                    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                    -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) `
                    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger `
        -Principal $Principal -Settings $Settings -Force | Out-Null

    Set-Content -Path $VersionTag -Value $Version -Encoding UTF8
    Write-Output "Installed LabIdleLogoff v$Version (idle=$IdleLimitSeconds s, poll=$PollSeconds s)"
    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Error $_
    Stop-Transcript | Out-Null
    exit 1
}