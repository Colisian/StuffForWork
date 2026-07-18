<#
.SYNOPSIS
    Intune Win32 detection script for the Disk Space Monitor.

.DESCRIPTION
    Detected = writes to stdout and exits 0. Not detected = exits 1 with no output.
    Checks that the scheduled task, the installed script, and the config file all exist.

.NOTES
    Author:  Colisian (cmcleod1@umd.edu)
    Date:    2026-07-14
    Version: 2.0
#>
$task   = Get-ScheduledTask -TaskName 'Disk Space Monitor' -ErrorAction SilentlyContinue
$script = Test-Path 'C:\Program Files\DiskSpaceMonitor\Invoke-DiskSpaceCheck.ps1'
$config = Test-Path 'C:\ProgramData\DiskSpaceMonitor\config.json'

if ($task -and $script -and $config) {
    Write-Output 'Disk Space Monitor detected'
    exit 0
}
exit 1
