<#
.SYNOPSIS
Detects the Intune Win32 microfilm portrait display configuration.

.DESCRIPTION
Checks the 64-bit HKLM sentinel, saved original-state file, target count, and
every Rotation value previously changed by the installer.

Intune custom detection contract:
  exit 0 plus STDOUT = detected
  non-zero exit      = not detected

Configure Intune to run this script as a 64-bit process and without logged-on
user credentials. The script intentionally remains silent when not detected.

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-08-27
Version: 1.0.0
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

$expectedVersion = '1.0.0'
$expectedRotation = 2
$sentinelSubKey = 'SOFTWARE\UMD Libraries\MicrofilmPortraitDisplay'
$statePath = Join-Path -Path $env:ProgramData -ChildPath 'UMD Libraries\MicrofilmPortraitDisplay\OriginalRotation.json'

function Get-Hklm64Value {
    <#
    .SYNOPSIS
    Reads a value through the 64-bit HKLM registry view.

    .PARAMETER SubKey
    Registry subkey below HKEY_LOCAL_MACHINE.

    .PARAMETER Name
    Registry value name.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-27
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SubKey,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key = $baseKey.OpenSubKey($SubKey, $false)
        if (-not $key) {
            return $null
        }

        try {
            return $key.GetValue($Name, $null)
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
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        exit 1
    }

    $sentinelVersion = [string](Get-Hklm64Value -SubKey $sentinelSubKey -Name 'Version')
    $sentinelRotation = Get-Hklm64Value -SubKey $sentinelSubKey -Name 'DesiredRotation'
    $sentinelTargetCount = Get-Hklm64Value -SubKey $sentinelSubKey -Name 'TargetCount'

    if ($sentinelVersion -ne $expectedVersion -or
        $null -eq $sentinelRotation -or [int]$sentinelRotation -ne $expectedRotation -or
        $null -eq $sentinelTargetCount) {
        exit 1
    }

    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $savedValues = @($state.Values)
    if ([int]$state.SchemaVersion -ne 1 -or
        $savedValues.Count -eq 0 -or
        $savedValues.Count -ne [int]$sentinelTargetCount) {
        exit 1
    }

    foreach ($savedValue in $savedValues) {
        $rotation = Get-Hklm64Value -SubKey ([string]$savedValue.RegistrySubKey) -Name 'Rotation'
        if ($null -eq $rotation -or [int]$rotation -ne $expectedRotation) {
            exit 1
        }
    }

    Write-Output "Detected: microfilm displays use portrait rotation (version $expectedVersion)."
    exit 0
}
catch {
    exit 1
}
