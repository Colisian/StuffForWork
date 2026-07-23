<#
.SYNOPSIS
    Intune Win32 detection rule for LabIdleLogoff.
.DESCRIPTION
    Detected when the scheduled task and watcher payload exist AND version.txt
    matches $ExpectedVer. The version gate is what rolls out updates: bumping
    the version here + in Install-IdleLogoff.ps1 makes already-installed
    machines report "not installed" so Intune reinstalls the new payload.
    Keep $ExpectedVer in sync with the install script's -Version default,
    or Intune will reinstall in a loop.
.NOTES
    Author  : Oji McLeod (cmcleod1@umd.edu)
    Date    : 2026-07-22
    Version : 1.2.0
#>
$TaskName    = 'LabIdleLogoff'
$Watcher     = 'C:\ProgramData\LabIdleLogoff\Watch-Idle.ps1'
$VersionTag  = 'C:\ProgramData\LabIdleLogoff\version.txt'
$ExpectedVer = '1.2.0'   # keep in sync with Install-IdleLogoff.ps1

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task)                { exit 0 }   # no output -> not installed
if (-not (Test-Path $Watcher)) { exit 0 }   # payload missing -> not installed

if (Test-Path $VersionTag) {
    $ver = (Get-Content $VersionTag -Raw).Trim()
    if ($ver -eq $ExpectedVer) {
        Write-Output "LabIdleLogoff v$ver present"
        exit 0
    }
}
exit 0   # version mismatch/missing -> not installed, triggers upgrade
