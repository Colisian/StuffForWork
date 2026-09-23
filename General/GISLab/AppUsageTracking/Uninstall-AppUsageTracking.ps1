#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Removes the GIS Lab application-usage harvester.

.DESCRIPTION
    Removes the scheduled task and detection sentinel. By default, collected
    data is retained in a timestamped directory and process auditing remains
    enabled because another security control may depend on it.

.NOTES
    Author: UMD Libraries ITFO
    Date: 2026-09-07
    Version: 2.0.0
    Run as Administrator or as SYSTEM through Intune.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallDir,
    [string]$TaskName = 'LabAppUsageHarvester',
    [switch]$PurgeData,
    [switch]$DisableAuditing,
    [switch]$DisableCmdLine
)

$ErrorActionPreference = 'Stop'
$registryPath = 'HKLM:\SOFTWARE\UMDLibraries\LabAppUsageTracking'
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $installedPath = (Get-ItemProperty -Path $registryPath -Name InstallDir `
        -ErrorAction SilentlyContinue).InstallDir
    $InstallDir = if ($installedPath) { $installedPath } else { "$env:ProgramData\LabUsage" }
}

$deploymentLogDir = "$env:ProgramData\UMDLibraries\AppUsage"
if (-not (Test-Path -LiteralPath $deploymentLogDir)) {
    New-Item -Path $deploymentLogDir -ItemType Directory -Force | Out-Null
}
$uninstallLog = Join-Path $deploymentLogDir 'AppUsageTracking-Uninstall.log'
Start-Transcript -Path $uninstallLog -Append -ErrorAction SilentlyContinue | Out-Null

try {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task -and $PSCmdlet.ShouldProcess($TaskName, 'Stop and unregister scheduled task')) {
        if ($task.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            $deadline = (Get-Date).AddSeconds(15)
            do {
                Start-Sleep -Milliseconds 500
                $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            } while ($task -and $task.State -eq 'Running' -and (Get-Date) -lt $deadline)
            if ($task -and $task.State -eq 'Running') {
                throw "Scheduled task '$TaskName' did not stop within 15 seconds."
            }
        }
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "[-] Scheduled task '$TaskName' removed."
    }

    if (Test-Path -LiteralPath $InstallDir) {
        if ($PurgeData) {
            if ($PSCmdlet.ShouldProcess($InstallDir, 'Delete application-usage data')) {
                $acl = Get-Acl -LiteralPath $InstallDir
                $acl.SetAccessRuleProtection($false, $true)
                Set-Acl -LiteralPath $InstallDir -AclObject $acl
                Remove-Item -LiteralPath $InstallDir -Recurse -Force
                Write-Host "[-] Data purged: $InstallDir"
            }
        } else {
            $retainedPath = "$InstallDir.retained-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            if ($PSCmdlet.ShouldProcess($InstallDir, "Retain data at $retainedPath")) {
                Move-Item -LiteralPath $InstallDir -Destination $retainedPath
                Write-Host "[+] Data retained: $retainedPath"
            }
        }
    }

    if ($DisableAuditing -and
        $PSCmdlet.ShouldProcess('Process Creation and Process Termination', 'Disable success auditing')) {
        $auditGuids = @(
            '{0CCE922B-69AE-11D9-BED3-505054503030}',
            '{0CCE922C-69AE-11D9-BED3-505054503030}'
        )
        foreach ($auditGuid in $auditGuids) {
            & auditpol.exe /set "/subcategory:$auditGuid" /success:disable | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "auditpol failed for subcategory $auditGuid with exit code $LASTEXITCODE."
            }
        }
        Write-Host '[-] Process Creation and Process Termination success auditing disabled.'
    }

    if ($DisableCmdLine) {
        $auditRegistry = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
        if ((Test-Path -LiteralPath $auditRegistry) -and
            $PSCmdlet.ShouldProcess($auditRegistry, 'Remove command-line audit policy value')) {
            Remove-ItemProperty -Path $auditRegistry -Name 'ProcessCreationIncludeCmdLine_Enabled' `
                -Force -ErrorAction SilentlyContinue
        }
    }

    if ((Test-Path -LiteralPath $registryPath) -and
        $PSCmdlet.ShouldProcess($registryPath, 'Remove Intune detection sentinel')) {
        Remove-Item -LiteralPath $registryPath -Recurse -Force
    }

    Write-Host '[+] App usage tracking uninstall completed.'
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
