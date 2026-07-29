<#
.SYNOPSIS
    Intune Win32 app detection script for LIBR-SetTimeZoneEastern.

.DESCRIPTION
    Checks live device state rather than the registry marker alone, so the app
    self-heals: if a technician or an app changes the time zone, re-enables
    geolocation time zone detection, or sets w32time back to Manual, detection
    fails and Intune reinstalls on the next evaluation cycle.

    Conditions evaluated (all must pass):
      1. Registry marker exists with the expected Version.
      2. TimeZoneKeyName == 'Eastern Standard Time'.
      3. tzautoupdate Start == 4 (automatic time zone detection disabled).
      4. w32time startup type == Automatic.

.NOTES
    Intune Win32 detection script contract:
      exit 0 + STDOUT output  = DETECTED (installed)
      exit 0 + no output      = NOT detected
      non-zero exit           = NOT detected

    IMPORTANT: keep $ExpectedVersion in sync with the -Version value used by
    the install script. Bumping it forces a reinstall across the fleet.

    Configure the Win32 app with "Run script as 32-bit process on 64-bit
    clients = No" so HKLM:\SOFTWARE is not redirected to WOW6432Node.
#>

$ExpectedVersion  = '1.0.0'
$ExpectedTimeZone = 'Eastern Standard Time'

$MarkerPath = 'HKLM:\SOFTWARE\LIBR\Deployments\TimeZoneEastern'
$TzInfoPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation'
$TzAutoPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate'

try {
    # 1. Marker present with matching version
    if (-not (Test-Path -Path $MarkerPath)) { exit 1 }

    $marker = Get-ItemProperty -Path $MarkerPath -ErrorAction Stop
    if ($marker.Version -ne $ExpectedVersion) { exit 1 }

    # 2. Actual time zone
    $tzKeyName = (Get-ItemProperty -Path $TzInfoPath -Name 'TimeZoneKeyName' -ErrorAction Stop).TimeZoneKeyName
    if ($tzKeyName.Trim() -ne $ExpectedTimeZone) { exit 1 }

    # 3. Automatic time zone detection disabled
    if (Test-Path -Path $TzAutoPath) {
        $tzAutoStart = (Get-ItemProperty -Path $TzAutoPath -Name 'Start' -ErrorAction SilentlyContinue).Start
        if ($tzAutoStart -ne 4) { exit 1 }
    }

    # 4. Windows Time service set to Automatic
    $w32 = Get-Service -Name 'w32time' -ErrorAction SilentlyContinue
    if ($w32 -and $w32.StartType -ne 'Automatic') { exit 1 }

    # All checks passed
    Write-Output "Detected: $ExpectedTimeZone enforced, marker v$ExpectedVersion."
    exit 0
}
catch {
    # Any error means we cannot confirm compliance -> treat as not installed
    exit 1
}