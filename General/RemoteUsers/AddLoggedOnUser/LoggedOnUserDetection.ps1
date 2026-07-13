<#
.SYNOPSIS
    Intune detection: the logged-on user is a member of Remote Desktop Users.
.DESCRIPTION
    Detected/compliant = exit 0 with stdout; not detected = exit 1.
    The user is resolved from the most recently used non-special profile
    (preferring a loaded one; falls back to the last-used profile when nobody
    is logged on, e.g. detection runs at the lock screen). Membership is
    compared by SID via the ADSI WinNT provider - Get-LocalGroupMember throws
    on orphaned or Entra SIDs, so ADSI is deliberate.

    NOTE: detection is tied to the CURRENT user, so on shared devices a new
    user logging in flips the device non-compliant until the app reinstalls.

    Keep Get-LoggedOnUserSid in sync with the copies in
    AddLoggedOnUser.ps1 and RemoveLoggedOnUser.ps1.
.NOTES
    Author:  cmcleod1@umd.edu
    Date:    2026-07-13
    Version: 2.0
#>

$ErrorActionPreference = 'Stop'

function Get-LoggedOnUserSid {
    [CmdletBinding()]
    param()
    $profiles = Get-CimInstance -ClassName Win32_UserProfile -Filter 'Special=FALSE' |
        Sort-Object -Property LastUseTime -Descending
    # Prefer a loaded profile (active session); otherwise last logged-on user
    $userProfile = ($profiles | Where-Object { $_.Loaded } | Select-Object -First 1)
    if (-not $userProfile) { $userProfile = $profiles | Select-Object -First 1 }
    if ($userProfile) { return $userProfile.SID }
    return $null
}

try {
    $userSid = Get-LoggedOnUserSid
    if (-not $userSid) {
        exit 1
    }

    # Resolve the (possibly localized) group name from its well-known SID
    $groupName = (Get-LocalGroup -SID 'S-1-5-32-555').Name
    $group = [ADSI]"WinNT://$env:COMPUTERNAME/$groupName,group"

    $memberSids = @($group.Invoke('Members')) | ForEach-Object {
        $bytes = $_.GetType().InvokeMember('objectSid', 'GetProperty', $null, $_, $null)
        (New-Object System.Security.Principal.SecurityIdentifier($bytes, 0)).Value
    }

    if ($memberSids -contains $userSid) {
        Write-Host "Compliant: logged-on user ($userSid) is a member of Remote Desktop Users."
        exit 0
    }

    exit 1
} catch {
    # Any failure counts as not detected so Intune remediates
    exit 1
}
