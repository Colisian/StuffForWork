#Requires -Version 5.1

<#
.SYNOPSIS
    Heartbeats an active guest session so its end time can be reconstructed.

.DESCRIPTION
    Started hidden by the broker immediately after a LaunchAndExit launch, running
    as the same guest account. Writes the current time into the session state file
    every heartbeat interval and never exits on its own — Windows terminates it
    when the guest signs out.

    The session end is therefore not recorded here. The next broker start reads the
    state file, sees an unfinished session, and appends the SessionEnd row using
    the final heartbeat as the end time.

    That indirection is deliberate. A process cannot reliably write anything during
    logoff: Windows kills it, killed processes do not run finally blocks, and
    SessionEnding handlers are unreliable under logoff timing. Reconstructing from
    a heartbeat also closes out sessions lost to a crash or a power cut, which
    writing-on-exit never could.

    Measures the whole Windows session rather than the lifetime of the launched
    application, so a patron who closes Edge and keeps working still counts.

    Accuracy is one heartbeat interval, 60 seconds by default.

.PARAMETER GuestAccount
    The libguestN account that authenticated.

.PARAMETER SessionId
    GUID correlating this session with its SignIn row.

.PARAMETER ApplicationId
    Allowlist entry that was launched.

.PARAMETER StatePath
    Session state file. Pre-created by the installer with Users:Modify so a guest
    can overwrite its contents.

.PARAMETER StartedAt
    Round-trip formatted authentication time.

.PARAMETER HeartbeatSeconds
    Seconds between heartbeats. Also the accuracy of the recorded end time.

.NOTES
    Author:  Oji / UMD Libraries
    Date:    2026-07-27
    Version: 0.3.2

    Not intended to be run by hand. Every failure path exits silently: an audit
    row is never worth disturbing a patron session over.
#>

[CmdletBinding()]
param(
    [string]$GuestAccount,
    [string]$SessionId,
    [string]$ApplicationId,
    [string]$StatePath,
    [string]$StartedAt,
    [int]$HeartbeatSeconds = 60
)

begin {
    $ErrorActionPreference = 'Stop'
}

end {
    if ([string]::IsNullOrWhiteSpace($StatePath) -or [string]::IsNullOrWhiteSpace($GuestAccount)) {
        exit 0
    }

    $startedAtValue = if ($StartedAt) { $StartedAt } else { (Get-Date).ToString('o') }

    while ($true) {
        try {
            $state = [pscustomobject]@{
                SchemaVersion = 1
                SessionId     = $SessionId
                GuestAccount  = $GuestAccount
                Application   = $ApplicationId
                ComputerName  = [Environment]::MachineName
                StartedAt     = $startedAtValue
                LastSeen      = (Get-Date).ToString('o')
            }

            # Overwrite in place rather than delete and recreate. The installer
            # grants Users:Modify on this specific file; a recreated file would
            # inherit the folder ACL, which is read-only for Users, and the next
            # guest could not write it.
            Set-Content -LiteralPath $StatePath -Value ($state | ConvertTo-Json -Compress) -Encoding UTF8
        }
        catch {
            # A missed heartbeat only costs accuracy, never the session.
        }

        Start-Sleep -Seconds $HeartbeatSeconds
    }
}
