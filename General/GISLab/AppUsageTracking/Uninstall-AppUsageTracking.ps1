<#
.SYNOPSIS
    Removes the Lab App Usage Harvester: unregisters the scheduled task,
    optionally reverts process auditing, and cleans (or preserves) the
    collected data.

.DESCRIPTION
    Companion to Setup-AppUsageTracking.ps1. Idempotent: safe to re-run.

    Default behavior on Intune uninstall:
      - Unregister the LabAppUsageHarvester scheduled task
      - Preserve the collected CSV by moving the data folder aside to
        C:\ProgramData\LabUsage.retained-<timestamp>
      - Leave process auditing enabled (other tools may depend on it)

    Switches:
      -PurgeData        Fully delete C:\ProgramData\LabUsage instead of
                        moving it aside. Use for a hard reset.
      -DisableAuditing  Revert Process Creation + Process Termination
                        auditing to "no auditing." Only set this if you
                        know nothing else on the machine needs 4688/4689.
      -DisableCmdLine   Also clears the ProcessCreationIncludeCmdLine_Enabled
                        policy that Setup can optionally set.

.NOTES
    Run as Administrator or as SYSTEM (Intune Win32 uninstall context).
    Author: UMD Libraries ITFO
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallDir  = "$env:ProgramData\LabUsage",
    [string]$TaskName    = 'LabAppUsageHarvester',
    [switch]$PurgeData,
    [switch]$DisableAuditing,
    [switch]$DisableCmdLine
)

$ErrorActionPreference = 'Stop'

# --- 1. Unregister the scheduled task --------------------------------------
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    if ($PSCmdlet.ShouldProcess($TaskName, 'Unregister scheduled task')) {
        # Kill any in-flight harvest first: a live transcript handle on
        # harvest.log would make the data-folder move below throw.
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "[-] Scheduled task '$TaskName' removed."
    }
} else {
    Write-Host "[=] Scheduled task '$TaskName' not present (already removed)."
}

# --- 2. Handle the data folder ---------------------------------------------
if (Test-Path $InstallDir) {
    if ($PurgeData) {
        if ($PSCmdlet.ShouldProcess($InstallDir, 'Delete data folder')) {
            # Restore inheritance so Remove-Item can walk the tree even if
            # ACLs were tightened during setup.
            try {
                $acl = Get-Acl $InstallDir
                $acl.SetAccessRuleProtection($false, $true)
                Set-Acl -Path $InstallDir -AclObject $acl
            } catch {
                Write-Warning "Could not reset ACL on '$InstallDir': $_"
            }
            Remove-Item -Path $InstallDir -Recurse -Force
            Write-Host "[-] Data folder purged: $InstallDir"
        }
    } else {
        $stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
        $retained = "$InstallDir.retained-$stamp"
        if ($PSCmdlet.ShouldProcess($InstallDir, "Rename to $retained (preserve CSV)")) {
            Move-Item -Path $InstallDir -Destination $retained -Force
            Write-Host "[+] Data preserved at: $retained"
        }
    }
} else {
    Write-Host "[=] Data folder '$InstallDir' not present."
}

# --- 3. Optionally revert audit policy -------------------------------------
if ($DisableAuditing) {
    if ($PSCmdlet.ShouldProcess('Process Creation/Termination', 'Disable auditing')) {
        # Subcategory GUIDs, not names - the names are localized (matches Setup).
        $sub = @{
            'Process Creation'    = '{0CCE922B-69AE-11D9-BED3-505054503030}'
            'Process Termination' = '{0CCE922C-69AE-11D9-BED3-505054503030}'
        }
        auditpol /set /subcategory:"$($sub['Process Creation'])"    /success:disable | Out-Null
        auditpol /set /subcategory:"$($sub['Process Termination'])" /success:disable | Out-Null
        Write-Host "[-] Process Creation + Termination auditing disabled."

        # Verify - GPO may re-enforce audit policy at next refresh.
        $check = @(
            @{ Name = 'Process Creation';    Result = (auditpol /get /subcategory:"$($sub['Process Creation'])"    | Out-String) }
            @{ Name = 'Process Termination'; Result = (auditpol /get /subcategory:"$($sub['Process Termination'])" | Out-String) }
        )
        foreach ($c in $check) {
            if ($c.Result -match 'Success') {
                Write-Warning "'$($c.Name)' still shows Success after disable - likely re-enforced by GPO."
            }
        }
    }
} else {
    Write-Host "[=] Audit policy left enabled (pass -DisableAuditing to revert)."
}

if ($DisableCmdLine) {
    $reg = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
    if (Test-Path $reg) {
        if ($PSCmdlet.ShouldProcess($reg, 'Clear ProcessCreationIncludeCmdLine_Enabled')) {
            Remove-ItemProperty -Path $reg -Name 'ProcessCreationIncludeCmdLine_Enabled' -Force -ErrorAction SilentlyContinue
            Write-Host "[-] Command-line capture policy cleared."
        }
    }
}

Write-Host "`nUninstall complete."
