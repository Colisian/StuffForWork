<#
.SYNOPSIS
    Uninstalls the LIBR Eastern Standard Time configuration package.

.DESCRIPTION
    Removes the registry detection marker and, by default, re-enables automatic
    (geolocation-based) time zone detection so the device returns to stock
    behavior.

    The time zone itself is intentionally NOT reverted -- there is no sensible
    "previous" value to restore, and leaving a public workstation on the wrong
    time zone causes TLS/Kerberos problems. Use -RevertTimeZoneTo to explicitly
    set a different zone if you need one.

    The w32time service is left as Automatic by default, since accurate time is
    desirable regardless of this package. Use -RevertW32TimeToManual to restore
    the Entra-joined default of Manual (Trigger Start).

.PARAMETER RevertTimeZoneTo
    Optional Windows time zone ID to set during uninstall. Omit to leave the
    current time zone unchanged.

.PARAMETER KeepAutoTimeZoneDisabled
    Leave geolocation-based time zone detection disabled (do not re-enable).

.PARAMETER RevertW32TimeToManual
    Set the Windows Time service back to Manual startup.

.NOTES
    Exit codes: 0 = Success, 1 = Failure
    Log: C:\ProgramData\IntuneLogs\LIBR-SetTimeZoneEastern.log
#>

[CmdletBinding()]
param(
    [string]$RevertTimeZoneTo,
    [switch]$KeepAutoTimeZoneDisabled,
    [switch]$RevertW32TimeToManual
)

#region --- 64-bit relaunch guard (sysnative) ---
if ($env:PROCESSOR_ARCHITEW6432 -eq 'AMD64') {
    $sysnative = Join-Path -Path $env:WINDIR -ChildPath 'sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -Path $sysnative) {
        $relaunchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        if ($RevertTimeZoneTo)          { $relaunchArgs += @('-RevertTimeZoneTo', "`"$RevertTimeZoneTo`"") }
        if ($KeepAutoTimeZoneDisabled)  { $relaunchArgs += '-KeepAutoTimeZoneDisabled' }
        if ($RevertW32TimeToManual)     { $relaunchArgs += '-RevertW32TimeToManual' }
        $proc = Start-Process -FilePath $sysnative -ArgumentList $relaunchArgs -Wait -PassThru -WindowStyle Hidden
        exit $proc.ExitCode
    }
}
#endregion

$LogDir     = Join-Path -Path $env:ProgramData -ChildPath 'IntuneLogs'
$LogPath    = Join-Path -Path $LogDir -ChildPath 'LIBR-SetTimeZoneEastern.log'
$MarkerPath = 'HKLM:\SOFTWARE\LIBR\Deployments\TimeZoneEastern'
$TzAutoPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate'

if (-not (Test-Path -Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Output $line
    try { Add-Content -Path $LogPath -Value $line -ErrorAction Stop } catch { }
}

Write-Log '=================================================='
Write-Log 'Starting LIBR-SetTimeZoneEastern UNINSTALL'

$exitCode = 0

try {
    # 1. Optional time zone revert
    if ($RevertTimeZoneTo) {
        Set-TimeZone -Id $RevertTimeZoneTo -ErrorAction Stop
        Write-Log "Reverted time zone to '$RevertTimeZoneTo'."
    }
    else {
        Write-Log "Time zone left unchanged at '$((Get-TimeZone).Id)'."
    }

    # 2. Re-enable automatic time zone detection unless told otherwise
    if (-not $KeepAutoTimeZoneDisabled -and (Test-Path -Path $TzAutoPath)) {
        Set-ItemProperty -Path $TzAutoPath -Name 'Start' -Value 3 -Type DWord -Force
        Write-Log 'Re-enabled automatic time zone detection (tzautoupdate Start=3).'
    }
    else {
        Write-Log 'Automatic time zone detection left disabled.'
    }

    # 3. Optional w32time revert
    if ($RevertW32TimeToManual) {
        if (Get-Service -Name 'w32time' -ErrorAction SilentlyContinue) {
            Set-Service -Name 'w32time' -StartupType Manual -ErrorAction Stop
            Write-Log 'Reverted w32time startup type to Manual.'
        }
    }
    else {
        Write-Log 'w32time startup type left as-is.'
    }

    # 4. Remove the detection marker
    if (Test-Path -Path $MarkerPath) {
        Remove-Item -Path $MarkerPath -Recurse -Force
        Write-Log "Removed marker key $MarkerPath."
    }
    else {
        Write-Log 'Marker key not present; nothing to remove.'
    }

    Write-Log 'Uninstall completed successfully.'
}
catch {
    Write-Log "FAILURE: $($_.Exception.Message)" 'ERROR'
    $exitCode = 1
}

Write-Log "Exiting with code $exitCode."
Write-Log '=================================================='
exit $exitCode