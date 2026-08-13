<#
.SYNOPSIS
Intune Win32 app custom detection rule for the device-mapped default printer
configuration.

.DESCRIPTION
This app changes state (registry values and a scheduled task) rather than
installing files under Program Files, so detection checks the sentinel written
by Install-DefaultPrinter.ps1 plus the two artifacts that actually do the work:
the staged per-user payload and the logon task.

The expected printer name and version are hardcoded here because Intune runs
detection scripts standalone, with no access to the bundled DefaultPrinter.json.
Keep both values in sync with that file when you version the package.

Intune contract:
  exit 0 + STDOUT output  = DETECTED (installed)
  exit 0 + no output      = NOT detected
  non-zero exit           = NOT detected

Configure in Intune with:
  Run script as 32-bit process on 64-bit clients : No
  Enforce script signature check                 : No

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-08-12
Version: 1.0.0
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

# ---- Config: keep $expectedVersion in sync with DefaultPrinter.json ----
# Deliberately does NOT check which printer was configured. The install script
# already resolved the device's rule and would have failed if the queue was
# missing, so re-deriving the mapping here would mean maintaining the rule table
# in two places for no gain. Bumping Version in DefaultPrinter.json (and here)
# is what forces a re-run after a mapping change.
$expectedVersion = '2.0.0'
$sentinelPath = 'SOFTWARE\UMD\Pharos\DefaultPrinter'
$payloadPath = Join-Path -Path $env:ProgramData -ChildPath 'UMD\Pharos\Set-DefaultPrinter.User.ps1'
$taskName = 'Set-DefaultPrinter'
$taskPath = '\UMD\'

function Get-Hklm64Value {
    <#
    .SYNOPSIS
    Reads an HKLM value through the 64-bit registry view.

    .PARAMETER Path
    Subkey path below HKLM.

    .PARAMETER Name
    Value name.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key = $baseKey.OpenSubKey($Path)
        if (-not $key) {
            return $null
        }

        try {
            return $key.GetValue($Name)
        }
        finally {
            $key.Dispose()
        }
    }
    finally {
        $baseKey.Dispose()
    }
}

try {
    $reasons = @()

    # Recorded for the operator's benefit only; a device out of scope stores
    # '(out of scope)' here and is still correctly reported as installed.
    $sentinelPrinter = [string](Get-Hklm64Value -Path $sentinelPath -Name 'PrinterName')
    $sentinelVersion = [string](Get-Hklm64Value -Path $sentinelPath -Name 'Version')

    if ([string]::IsNullOrWhiteSpace($sentinelPrinter)) {
        $reasons += 'sentinel PrinterName missing'
    }

    if ($sentinelVersion -ne $expectedVersion) {
        $reasons += "sentinel Version is '$sentinelVersion', expected '$expectedVersion'"
    }

    if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
        $reasons += "per-user payload missing ($payloadPath)"
    }

    $task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    if (-not $task) {
        $reasons += "logon task missing ($taskPath$taskName)"
    }
    elseif ($task.State -eq 'Disabled') {
        $reasons += "logon task $taskPath$taskName is disabled"
    }

    if ($reasons.Count -eq 0) {
        # DETECTED - any STDOUT text plus exit 0 satisfies Intune
        Write-Output "Detected: default printer '$sentinelPrinter' enforced (version $expectedVersion)."
        exit 0
    }

    # NOT detected - stay silent on STDOUT
    exit 1
}
catch {
    # Never report "installed" on an unexpected error
    exit 1
}
