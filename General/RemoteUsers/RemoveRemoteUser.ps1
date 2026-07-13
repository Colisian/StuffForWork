<#
.SYNOPSIS
    Removes Authenticated Users from the local Remote Desktop Users group.
.DESCRIPTION
    Intune Win32 uninstall script. Runs non-interactively as SYSTEM (64-bit via
    uninstall.cmd SysNative wrapper). Operates on well-known SIDs so behavior is
    locale-independent:
        S-1-5-32-555 = Remote Desktop Users
        S-1-5-11     = Authenticated Users
.NOTES
    Author:  cmcleod1@umd.edu
    Date:    2026-07-13
    Version: 2.0
#>

$ErrorActionPreference = 'Stop'
$exitCode = 1

# Loaded explicitly so the typed catch below can resolve MemberNotFoundException
Import-Module Microsoft.PowerShell.LocalAccounts

$logDir = 'C:\ProgramData\RemoteUsers'
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path (Join-Path $logDir 'RemoveRemoteUser.log') -Force

try {
    Write-Host "=== Remote Desktop Users Uninstall Script v2.0 ==="
    Write-Host "Running as: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-Host "64-bit process: $([Environment]::Is64BitProcess)"

    $authenticatedUsers = [System.Security.Principal.SecurityIdentifier]'S-1-5-11'

    try {
        Remove-LocalGroupMember -SID 'S-1-5-32-555' -Member $authenticatedUsers
        Write-Host "Removed Authenticated Users from the Remote Desktop Users group."
    } catch [Microsoft.PowerShell.Commands.MemberNotFoundException] {
        Write-Host "Authenticated Users is not a member - nothing to do."
    }

    $exitCode = 0
} catch {
    Write-Host "ERROR: $_"
    Write-Host "Exception Type: $($_.Exception.GetType().FullName)"
    $exitCode = 1
} finally {
    Stop-Transcript
}

exit $exitCode
