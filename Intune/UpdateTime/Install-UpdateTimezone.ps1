<#
.SYNOPSIS
    Sets the device time zone to Eastern Standard Time and hardens time sync.

.DESCRIPTION
    Intended for deployment as an Intune Win32 app in SYSTEM context.

    Actions performed:
      1. Relaunches itself in 64-bit PowerShell (sysnative) if started 32-bit,
         so HKLM:\SOFTWARE writes are not redirected into WOW6432Node.
      2. Sets the time zone to 'Eastern Standard Time' (handles EST/EDT
         automatically -- there is no separate EDT time zone ID).
      3. Disables automatic (geolocation-based) time zone detection so nothing
         overrides the enforced setting on fixed-location public workstations.
      4. Sets the Windows Time service (w32time) to Automatic and starts it.
         On Entra-joined devices it defaults to Manual/Trigger Start and is
         usually stopped, which causes 'w32tm /resync' to fail with 0x80070426.
      5. Optionally configures an explicit NTP peer list.
      6. Forces a time resync (non-fatal -- network may be unavailable at ESP).
      7. Writes a registry marker used by the detection script.

.PARAMETER TimeZoneId
    Windows time zone ID to enforce. Default: 'Eastern Standard Time'.

.PARAMETER NtpPeerList
    Optional space-delimited NTP peer list, e.g. "ntp.umd.edu,0x9".
    Leave empty to keep the existing time source configuration.

.PARAMETER Version
    Package version stamped into the registry marker. Must match the value in
    the detection script.

.NOTES
    Exit codes:
      0    = Success
      1    = Failure
      3010 = Soft reboot required (not used by this package)

    Log: C:\ProgramData\IntuneLogs\LIBR-SetTimeZoneEastern.log
#>

[CmdletBinding()]
param(
    [string]$TimeZoneId  = 'Eastern Standard Time',
    [string]$NtpPeerList = '',
    [string]$Version     = '1.0.0'
)

#region --- 64-bit relaunch guard (sysnative) ---
if ($env:PROCESSOR_ARCHITEW6432 -eq 'AMD64') {
    $sysnative = Join-Path -Path $env:WINDIR -ChildPath 'sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -Path $sysnative) {
        $relaunchArgs = @(
            '-NoProfile'
            '-ExecutionPolicy', 'Bypass'
            '-File', "`"$PSCommandPath`""
            '-TimeZoneId', "`"$TimeZoneId`""
            '-NtpPeerList', "`"$NtpPeerList`""
            '-Version', "`"$Version`""
        )
        $proc = Start-Process -FilePath $sysnative -ArgumentList $relaunchArgs -Wait -PassThru -WindowStyle Hidden
        exit $proc.ExitCode
    }
}
#endregion

#region --- Constants and logging ---
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
#endregion

Write-Log '=================================================='
Write-Log "Starting LIBR-SetTimeZoneEastern v$Version"
Write-Log "Running as: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Process bitness: $(if ([Environment]::Is64BitProcess) { '64-bit' } else { '32-bit' })"
Write-Log "Target time zone: $TimeZoneId"

$exitCode = 0

try {
    # -----------------------------------------------------------------
    # 1. Disable automatic (geolocation) time zone detection
    #    tzautoupdate Start: 3 = enabled, 4 = disabled
    # -----------------------------------------------------------------
    if (Test-Path -Path $TzAutoPath) {
        $currentStart = (Get-ItemProperty -Path $TzAutoPath -Name 'Start' -ErrorAction SilentlyContinue).Start
        if ($currentStart -ne 4) {
            Set-ItemProperty -Path $TzAutoPath -Name 'Start' -Value 4 -Type DWord -Force
            Write-Log "Disabled automatic time zone detection (tzautoupdate Start: $currentStart -> 4)."
        }
        else {
            Write-Log 'Automatic time zone detection already disabled.'
        }
    }
    else {
        Write-Log 'tzautoupdate service key not present; skipping.' 'WARN'
    }

    # -----------------------------------------------------------------
    # 2. Set the time zone
    # -----------------------------------------------------------------
    $before = (Get-TimeZone -ErrorAction SilentlyContinue).Id
    Write-Log "Time zone before change: '$before'."

    if ($before -eq $TimeZoneId) {
        Write-Log 'Time zone already correct; no change needed.'
    }
    else {
        try {
            Set-TimeZone -Id $TimeZoneId -ErrorAction Stop
            Write-Log "Set-TimeZone applied: '$TimeZoneId'."
        }
        catch {
            Write-Log "Set-TimeZone failed ($($_.Exception.Message)); falling back to tzutil.exe." 'WARN'
            $tzutil = Join-Path -Path $env:WINDIR -ChildPath 'System32\tzutil.exe'
            $null = & $tzutil /s "$TimeZoneId" 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "tzutil.exe failed with exit code $LASTEXITCODE."
            }
            Write-Log "tzutil fallback applied: '$TimeZoneId'."
        }
    }

    # -----------------------------------------------------------------
    # 3. Windows Time service: Automatic + running
    # -----------------------------------------------------------------
    $w32 = Get-Service -Name 'w32time' -ErrorAction SilentlyContinue
    if ($w32) {
        if ($w32.StartType -ne 'Automatic') {
            Set-Service -Name 'w32time' -StartupType Automatic -ErrorAction Stop
            Write-Log "w32time startup type changed: $($w32.StartType) -> Automatic."
        }
        else {
            Write-Log 'w32time startup type already Automatic.'
        }

        if ((Get-Service -Name 'w32time').Status -ne 'Running') {
            Start-Service -Name 'w32time' -ErrorAction Stop
            Write-Log 'Started w32time service.'
        }
        else {
            Write-Log 'w32time service already running.'
        }
    }
    else {
        Write-Log 'w32time service not found; skipping time sync configuration.' 'WARN'
    }

    # -----------------------------------------------------------------
    # 4. Optional explicit NTP peer list
    # -----------------------------------------------------------------
    if (-not [string]::IsNullOrWhiteSpace($NtpPeerList) -and $w32) {
        $w32tm = Join-Path -Path $env:WINDIR -ChildPath 'System32\w32tm.exe'
        $cfg = & $w32tm /config /manualpeerlist:"$NtpPeerList" /syncfromflags:manual /update 2>&1
        Write-Log "w32tm /config result: $cfg"
        Restart-Service -Name 'w32time' -Force -ErrorAction SilentlyContinue
        Write-Log 'Restarted w32time to apply peer list.'
    }

    # -----------------------------------------------------------------
    # 5. Force a resync (non-fatal -- network may not be up during ESP)
    # -----------------------------------------------------------------
    if ($w32) {
        $w32tm  = Join-Path -Path $env:WINDIR -ChildPath 'System32\w32tm.exe'
        $resync = & $w32tm /resync /force 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Time resync succeeded: $resync"
        }
        else {
            Write-Log "Time resync did not succeed (non-fatal): $resync" 'WARN'
        }
        $source = & $w32tm /query /source 2>&1
        Write-Log "Current time source: $source"
    }

    # -----------------------------------------------------------------
    # 6. Verify and write the detection marker
    # -----------------------------------------------------------------
    $after = (Get-TimeZone).Id
    if ($after -ne $TimeZoneId) {
        throw "Verification failed: time zone is '$after', expected '$TimeZoneId'."
    }

    if (-not (Test-Path -Path $MarkerPath)) {
        New-Item -Path $MarkerPath -Force | Out-Null
    }
    New-ItemProperty -Path $MarkerPath -Name 'Version'     -Value $Version    -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $MarkerPath -Name 'TimeZoneId'  -Value $TimeZoneId -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $MarkerPath -Name 'InstalledOn' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -PropertyType String -Force | Out-Null

    Write-Log "SUCCESS: time zone is '$after'. Local time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')."
    Write-Log "Marker written to $MarkerPath (Version $Version)."
    $exitCode = 0
}
catch {
    Write-Log "FAILURE: $($_.Exception.Message)" 'ERROR'
    Write-Log "At: $($_.InvocationInfo.PositionMessage)" 'ERROR'
    $exitCode = 1
}

Write-Log "Exiting with code $exitCode."
Write-Log '=================================================='
exit $exitCode