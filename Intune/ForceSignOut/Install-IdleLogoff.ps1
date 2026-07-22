# Install-IdleLogoff.ps1  — self-contained for Win32 "PowerShell script" installer type
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [int]$IdleLimitSeconds = 900,
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
    # --- Write watcher payload inline (no sibling file needed) ---
    $watcherBody = @'
param([int]$IdleLimit = 600, [int]$Poll = 15)

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
    if ([Idle]::GetIdleSeconds() -ge $IdleLimit) {
        shutdown.exe /l /f
        break
    }
    Start-Sleep -Seconds $Poll
}
'@
    Set-Content -Path $Watcher -Value $watcherBody -Encoding UTF8

    # --- Register the per-user scheduled task ---
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $args  = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Watcher`" -IdleLimit $IdleLimitSeconds -Poll $PollSeconds"

    $Action    = New-ScheduledTaskAction -Execute $psExe -Argument $args
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