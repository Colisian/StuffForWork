<#
.SYNOPSIS
    Adds the currently logged-on user to the local Remote Desktop Users group.
.DESCRIPTION
    Intune Win32 install script. Runs non-interactively as SYSTEM (64-bit via
    install.cmd SysNative wrapper). The console user is resolved from the most
    recently used loaded, non-special profile (works for Entra-joined accounts)
    and added by SID, so no name parsing or localization issues. If no user is
    logged on, the script exits 1 rather than guessing - Intune will retry.

    Keep Get-LoggedOnUserSid in sync with the copies in
    RemoveLoggedOnUser.ps1 and LoggedOnUserDetection.ps1.
.NOTES
    Author:  cmcleod1@umd.edu
    Date:    2026-07-13
    Version: 2.0
#>

$ErrorActionPreference = 'Stop'
$exitCode = 1

# Loaded explicitly so the typed catch below can resolve MemberExistsException
Import-Module Microsoft.PowerShell.LocalAccounts

$logDir = 'C:\ProgramData\RemoteUsers'
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path (Join-Path $logDir 'AddLoggedOnUser.log') -Force

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
    Write-Host "=== Add Logged-On User to Remote Desktop Users v2.0 ==="
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
        Add-LocalGroupMember -SID 'S-1-5-32-555' -Member $sid
        Write-Host "Added '$userName' to the Remote Desktop Users group."
    } catch [Microsoft.PowerShell.Commands.MemberExistsException] {
        Write-Host "'$userName' is already a member - nothing to do."
    }

    # Marker is for troubleshooting only; detection derives state live
    $markerPath = Join-Path $logDir "RDPUser_$userSid.marker"
    "$userName`n$userSid`n$(Get-Date -Format o)" | Out-File -FilePath $markerPath -Encoding UTF8
    Write-Host "Created marker file: $markerPath"

    $exitCode = 0
} catch {
    Write-Host "ERROR: $_"
    Write-Host "Exception Type: $($_.Exception.GetType().FullName)"
    $exitCode = 1
} finally {
    Stop-Transcript
}

exit $exitCode
