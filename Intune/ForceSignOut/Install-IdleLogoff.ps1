<#
.SYNOPSIS
    Installs the LabIdleLogoff watcher: a per-user scheduled task that signs the
    interactive user off after a configurable idle period.

.DESCRIPTION
    Self-contained for the Intune Win32 "PowerShell script" installer type — no
    sibling files required. Writes the watcher payload to
    C:\ProgramData\LabIdleLogoff\Watch-Idle.ps1 and registers a scheduled task
    that runs it at logon for every member of the local Users group.

.NOTES
    Author  : Oji McLeod (cmcleod1@umd.edu)
    Date    : 2026-07-22
    Version : 1.1.0
#>
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [int]$IdleLimitSeconds = 900,
    [int]$PollSeconds      = 15,
    [string]$Version       = '1.1.0'
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
    # --- Write watcher payload inline (no sibling file needed) ---
    # NOTE: single-quoted here-string — everything inside is literal and is
    # evaluated at WATCHER runtime, not install time.
    $watcherBody = @'
param([int]$IdleLimit = 600, [int]$Poll = 15)

$log = 'C:\ProgramData\LabIdleLogoff\watch.log'
function Write-WatchLog { param($m) "$(Get-Date -Format s)  $m" | Add-Content -Path $log }

try {
    $sid = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    Write-WatchLog "Watcher started (IdleLimit=$IdleLimit, Poll=$Poll, User=$env:USERNAME, Session=$sid)"

    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Idle {
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static uint GetIdleSeconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        GetLastInputInfo(ref lii);
        return ((uint)Environment.TickCount - lii.dwTime) / 1000;
    }
}
"@

    while ($true) {
        $idle = [Idle]::GetIdleSeconds()
        if ($idle -ge $IdleLimit) {
            Write-WatchLog "Idle $idle s >= limit $IdleLimit s -> logging off $env:USERNAME (session $sid)"
            # logoff.exe -> WTSLogoffSession: works even when the workstation is
            # locked (secure desktop). shutdown /l -> ExitWindowsEx does NOT.
            logoff.exe $sid
            break
        }
        Start-Sleep -Seconds $Poll
    }
}
catch {
    Write-WatchLog "ERROR: $_"
    exit 1
}
'@
    Set-Content -Path $Watcher -Value $watcherBody -Encoding UTF8

    # --- Register the per-user scheduled task ---
    $psExe    = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $taskArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Watcher`" -IdleLimit $IdleLimitSeconds -Poll $PollSeconds"

    $Action    = New-ScheduledTaskAction -Execute $psExe -Argument $taskArgs
    $Trigger   = New-ScheduledTaskTrigger -AtLogOn
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
