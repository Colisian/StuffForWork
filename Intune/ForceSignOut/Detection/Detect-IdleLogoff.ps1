<#
.SYNOPSIS
    Intune Win32 detection rule for LabIdleLogoff.
.DESCRIPTION
    Detected when both the scheduled task and the watcher payload exist.
    Version is reported for visibility but is NOT a detection gate, so an
    install invoked with a different -Version does not trigger a reinstall loop.
.NOTES
    Author  : Oji McLeod (cmcleod1@umd.edu)
    Date    : 2026-07-22
    Version : 1.1.0
#>
$TaskName   = 'LabIdleLogoff'
$Watcher    = 'C:\ProgramData\LabIdleLogoff\Watch-Idle.ps1'
$VersionTag = 'C:\ProgramData\LabIdleLogoff\version.txt'

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task)             { exit 0 }   # no output -> not installed
if (-not (Test-Path $Watcher)) { exit 0 }   # payload missing -> not installed

$ver = if (Test-Path $VersionTag) { (Get-Content $VersionTag -Raw).Trim() } else { 'unknown' }
Write-Output "LabIdleLogoff v$ver present"
exit 0
