<#
.SYNOPSIS
    Removes the Disk Space Monitor scheduled task, installed script, and configuration.

.DESCRIPTION
    Unregisters the 'Disk Space Monitor' scheduled task and deletes both
    C:\Program Files\DiskSpaceMonitor and C:\ProgramData\DiskSpaceMonitor
    (config, state, and logs). Exit codes: 0 = success, 1 = failure.

.EXAMPLE
    PS> .\Uninstall-DiskSpaceMonitor.ps1

.NOTES
    Author:  Colisian (cmcleod1@umd.edu)
    Date:    2026-07-14
    Version: 2.0
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

$taskName   = 'Disk Space Monitor'
$installDir = 'C:\Program Files\DiskSpaceMonitor'
$dataDir    = 'C:\ProgramData\DiskSpaceMonitor'

try {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        if ($PSCmdlet.ShouldProcess($taskName, 'Unregister scheduled task')) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Output "Scheduled task '$taskName' removed."
        }
    }
    else {
        Write-Output "Scheduled task '$taskName' not found; nothing to unregister."
    }

    foreach ($dir in @($installDir, $dataDir)) {
        if (Test-Path $dir) {
            if ($PSCmdlet.ShouldProcess($dir, 'Remove directory')) {
                Remove-Item -Path $dir -Recurse -Force
                Write-Output "Removed $dir"
            }
        }
    }

    Write-Output 'Uninstall complete.'
    exit 0
}
catch {
    Write-Error "Uninstall failed: $($_.Exception.Message)"
    exit 1
}
