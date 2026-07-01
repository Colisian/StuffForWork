<#
.SYNOPSIS
    One-time setup on a lab PC: enables process auditing, deploys the harvester,
    registers a scheduled task, and ACLs the data folder against tampering.

.NOTES
    Run as Administrator (or via GPO startup script / Intune as SYSTEM).
    Idempotent: safe to re-run.
#>

[CmdletBinding()]
param(
    [string]$ScriptSource = "$PSScriptRoot\Harvest-AppUsage.ps1",
    [string]$InstallDir   = "$env:ProgramData\LabUsage",
    [int]   $IntervalMin  = 15,
    [switch]$IncludeCmdLine   # only set if your security review approves it
)

$ErrorActionPreference = 'Stop'

# --- 0. Preflight ----------------------------------------------------------
if (-not (Test-Path $ScriptSource)) {
    throw "Harvester source not found: $ScriptSource"
}

# --- 1. Folder + ACL (deny ordinary Users write/delete) --------------------
if (-not (Test-Path $InstallDir)) {
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
}
$acl = Get-Acl $InstallDir
$acl.SetAccessRuleProtection($true, $false)   # break inheritance
$rules = @(
    New-Object System.Security.AccessControl.FileSystemAccessRule(
        'SYSTEM','FullControl','ContainerInherit,ObjectInherit','None','Allow')
    New-Object System.Security.AccessControl.FileSystemAccessRule(
        'Administrators','FullControl','ContainerInherit,ObjectInherit','None','Allow')
    New-Object System.Security.AccessControl.FileSystemAccessRule(
        'Users','ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')
)
# Snapshot to array first — iterating the live AccessRuleCollection while
# removing from it can silently skip rules.
@($acl.Access) | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
$rules | ForEach-Object { $acl.AddAccessRule($_) }
Set-Acl -Path $InstallDir -AclObject $acl
Write-Host "[+] Data folder secured: $InstallDir"

# --- 2. Copy the harvester into place --------------------------------------
Copy-Item $ScriptSource (Join-Path $InstallDir 'Harvest-AppUsage.ps1') -Force
Write-Host "[+] Harvester deployed."

# --- 3. Enable process auditing --------------------------------------------
auditpol /set /subcategory:"Process Creation"    /success:enable | Out-Null
auditpol /set /subcategory:"Process Termination" /success:enable | Out-Null

# Verify — auditpol /set silently no-ops if Advanced Audit Policy is overridden
# by GPO (SCENoApplyLegacyAuditPolicy). This is the #1 silent-failure mode.
$auditCheck = @(
    @{ Name = 'Process Creation';    Result = (auditpol /get /subcategory:"Process Creation"    | Out-String) }
    @{ Name = 'Process Termination'; Result = (auditpol /get /subcategory:"Process Termination" | Out-String) }
)
foreach ($c in $auditCheck) {
    if ($c.Result -notmatch 'Success') {
        Write-Warning "'$($c.Name)' auditing does not show Success — likely overridden by GPO. Harvester will collect nothing until this is resolved."
    }
}
Write-Host "[+] Process Creation + Termination auditing enabled."

if ($IncludeCmdLine) {
    $reg = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
    New-Item -Path $reg -Force | Out-Null
    Set-ItemProperty $reg 'ProcessCreationIncludeCmdLine_Enabled' 1 -Type DWord
    Write-Host "[+] Command-line capture enabled (review security implications)."
}

# --- 4. Register scheduled task (SYSTEM, every N minutes) -------------------
$taskName = 'LabAppUsageHarvester'
$psExe    = (Get-Command powershell.exe).Source
$harvest  = Join-Path $InstallDir 'Harvest-AppUsage.ps1'

$action  = New-ScheduledTaskAction -Execute $psExe `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$harvest`""

# Boot trigger so the task resumes after reboot without waiting for the next
# interval. Repeating trigger needs an explicit RepetitionDuration; without it
# some Windows versions treat the schedule as one-shot.
$trigger = @(
    New-ScheduledTaskTrigger -AtStartup
    New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes $IntervalMin) `
        -RepetitionDuration ([TimeSpan]::MaxValue)
)

# Use the fully-qualified account name — the short form 'SYSTEM' breaks on
# non-English Windows locales.
$principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' `
                -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable `
                -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "[+] Scheduled task '$taskName' registered (every $IntervalMin min)."

Write-Host "`nSetup complete. First data will appear after the next interval."
Write-Host "CSV: $(Join-Path $InstallDir 'usage.csv')"