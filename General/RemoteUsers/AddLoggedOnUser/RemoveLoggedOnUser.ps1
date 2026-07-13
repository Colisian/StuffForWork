<#
.SYNOPSIS
    Removes the currently logged-on user from the local Remote Desktop Users group.
.DESCRIPTION
    Intune Win32 uninstall script. Runs non-interactively as SYSTEM (64-bit via
    uninstall.cmd SysNative wrapper). The console user is resolved from the most
    recently used loaded, non-special profile and removed by SID. Note this only
    removes the CURRENT user - accounts added during earlier sessions stay in
    the group.

    Keep Get-LoggedOnUserSid in sync with the copies in
    AddLoggedOnUser.ps1 and LoggedOnUserDetection.ps1.
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
Start-Transcript -Path (Join-Path $logDir 'RemoveLoggedOnUser.log') -Force

function Get-LoggedOnUserSid {
    [CmdletBinding()]
    param()
    # A loaded, non-special profile means an interactive session is active
    $userProfile = Get-CimInstance -ClassName Win32_UserProfile `
        -Filter 'Special=FALSE AND Loaded=TRUE' |
        Sort-Object -Property LastUseTime -Descending |
        Select-Object -First 1
    if ($userProfile) { return $userProfile.SID }
    return $null
}

try {
    Write-Host "=== Remove Logged-On User from Remote Desktop Users v2.0 ==="
    Write-Host "Running as: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"

    $userSid = Get-LoggedOnUserSid
    if (-not $userSid) {
        throw 'No interactive user profile is currently loaded; cannot determine logged-on user.'
    }

    $sid = [System.Security.Principal.SecurityIdentifier]$userSid
    # Name resolution is best-effort, for logging only
    try { $userName = $sid.Translate([System.Security.Principal.NTAccount]).Value }
    catch { $userName = $userSid }
    Write-Host "Logged-on user: $userName ($userSid)"

    try {
        Remove-LocalGroupMember -SID 'S-1-5-32-555' -Member $sid
        Write-Host "Removed '$userName' from the Remote Desktop Users group."
    } catch [Microsoft.PowerShell.Commands.MemberNotFoundException] {
        Write-Host "'$userName' is not a member - nothing to do."
    }

    $markerPath = Join-Path $logDir "RDPUser_$userSid.marker"
    if (Test-Path $markerPath) {
        Remove-Item -Path $markerPath -Force
        Write-Host "Removed marker file: $markerPath"
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
