<#
.SYNOPSIS
    Intune detection: Authenticated Users is a member of Remote Desktop Users.
.DESCRIPTION
    Detected/compliant = exit 0 with stdout; not detected = exit 1.
    Members are enumerated via the ADSI WinNT provider deliberately:
    Get-LocalGroupMember throws on orphaned or Entra SIDs. Membership is
    compared by SID (S-1-5-11) so localized account names don't matter.
.NOTES
    Author:  cmcleod1@umd.edu
    Date:    2026-07-13
    Version: 2.0
#>

$ErrorActionPreference = 'Stop'

try {
    # Resolve the (possibly localized) group name from its well-known SID
    $groupName = (Get-LocalGroup -SID 'S-1-5-32-555').Name
    $group = [ADSI]"WinNT://$env:COMPUTERNAME/$groupName,group"

    $memberSids = @($group.Invoke('Members')) | ForEach-Object {
        $bytes = $_.GetType().InvokeMember('objectSid', 'GetProperty', $null, $_, $null)
        (New-Object System.Security.Principal.SecurityIdentifier($bytes, 0)).Value
    }

    if ($memberSids -contains 'S-1-5-11') {
        Write-Host "Compliant: Authenticated Users is a member of Remote Desktop Users."
        exit 0
    }

    exit 1
} catch {
    # Any failure counts as not detected so Intune remediates
    exit 1
}
