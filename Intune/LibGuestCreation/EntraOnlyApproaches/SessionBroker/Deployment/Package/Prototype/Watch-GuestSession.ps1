#Requires -Version 5.1

<#
.SYNOPSIS
    Records the end of a launch-and-exit guest session in sessions.csv.

.DESCRIPTION
    Started hidden by the broker immediately after a LaunchAndExit launch, running
    as the same guest account. Waits for the launched process to exit, then appends
    a SessionEnd row with the session duration.

    Exists because in LaunchAndExit mode the broker terminates right after the
    application starts, so nothing else is alive to observe the session ending.

    Appends with FILE_APPEND_DATA access only, matching the deployed ACL that lets
    Users add rows to sessions.csv but not rewrite or delete history.

    Not intended to be run by hand. Every failure path exits 0 silently: an audit
    row is never worth disturbing a patron session over.

.NOTES
    Author:  Oji / UMD Libraries
    Date:    2026-07-27
    Version: 0.3.1

    If the patron signs out of Windows while the application is still running,
    this process dies with the session and no SessionEnd row is written — the
    SignIn row will simply have no matching end. That is an accepted limit of
    watching from inside the session being watched.
#>

[CmdletBinding()]
param(
    [int]$WatchedProcessId,
    [string]$GuestAccount,
    [string]$SessionId,
    [string]$ApplicationId,
    [string]$CsvPath,
    [string]$StartedAt
)

begin {
    $ErrorActionPreference = 'Stop'
}

end {
    try {
        if (-not $WatchedProcessId -or [string]::IsNullOrWhiteSpace($CsvPath) -or
            [string]::IsNullOrWhiteSpace($GuestAccount)) {
            exit 0
        }

        $start = if ($StartedAt) {
            [datetime]::Parse($StartedAt, [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind)
        }
        else {
            Get-Date
        }

        # Blocks until the watched process exits. If it is already gone,
        # Wait-Process throws and the row is written immediately, which is the
        # right answer either way.
        try {
            Wait-Process -Id $WatchedProcessId -ErrorAction Stop
        }
        catch {
            # Already exited.
        }

        $durationMinutes = [math]::Round(((Get-Date) - $start).TotalMinutes, 1)

        $line = '{0},{1},{2},{3},{4},{5},{6},{7}' -f
            (Get-Date).ToString('o'),
            [Environment]::MachineName,
            'SessionEnd',
            $GuestAccount,
            $ApplicationId,
            $SessionId,
            $durationMinutes,
            'ApplicationExited'

        $stream = $null
        try {
            $stream = New-Object System.IO.FileStream(
                $CsvPath,
                [System.IO.FileMode]::Append,
                [System.Security.AccessControl.FileSystemRights]::AppendData,
                [System.IO.FileShare]::Read,
                4096,
                [System.IO.FileOptions]::None)
        }
        catch {
            $stream = $null
        }

        if ($stream) {
            try {
                $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
                $writer.WriteLine($line)
                $writer.Flush()
                $writer.Dispose()
            }
            finally {
                $stream.Dispose()
            }
        }
        else {
            Add-Content -LiteralPath $CsvPath -Value $line -Encoding UTF8
        }
    }
    catch {
        # Silent by design.
    }
    exit 0
}
