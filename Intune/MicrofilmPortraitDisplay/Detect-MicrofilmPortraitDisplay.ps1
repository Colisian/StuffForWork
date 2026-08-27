<#
.SYNOPSIS
Detects the Intune Win32 microfilm portrait display configuration.

.DESCRIPTION
Checks the 64-bit HKLM sentinel, saved original-state file, target counts,
every Rotation value previously changed by the installer, and every saved USB
3.x Device Manager power-management option.

Intune custom detection contract:
  exit 0 plus STDOUT = detected
  non-zero exit      = not detected

Configure Intune to run this script as a 64-bit process and without logged-on
user credentials. The script intentionally remains silent when not detected.

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-08-27
Version: 1.1.0
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

$expectedVersion = '1.1.0'
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
    Version: 1.1.0
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

function Get-UsbPowerSettingEnabled {
    <#
    .SYNOPSIS
    Reads one Device Manager power-management setting from root\wmi.

    .PARAMETER SettingClass
    WMI class holding the power-management setting.

    .PARAMETER InstanceName
    Exact WMI instance name associated with the Plug and Play device.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-27
    Version: 1.1.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('MSPower_DeviceEnable', 'MSPower_DeviceWakeEnable')]
        [string]$SettingClass,

        [Parameter(Mandatory)]
        [string]$InstanceName
    )

    $setting = Get-CimInstance -Namespace root\wmi -ClassName $SettingClass -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceName -eq $InstanceName } |
        Select-Object -First 1
    if (-not $setting) {
        return $null
    }

    return [bool]$setting.Enable
}

try {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        exit 1
    }

    $sentinelVersion = [string](Get-Hklm64Value -SubKey $sentinelSubKey -Name 'Version')
    $sentinelRotation = Get-Hklm64Value -SubKey $sentinelSubKey -Name 'DesiredRotation'
    $sentinelTargetCount = Get-Hklm64Value -SubKey $sentinelSubKey -Name 'TargetCount'
    $sentinelUsbPowerTargetCount = Get-Hklm64Value -SubKey $sentinelSubKey -Name 'UsbPowerTargetCount'

    if ($sentinelVersion -ne $expectedVersion -or
        $null -eq $sentinelRotation -or [int]$sentinelRotation -ne $expectedRotation -or
        $null -eq $sentinelTargetCount -or
        $null -eq $sentinelUsbPowerTargetCount) {
        exit 1
    }

    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $savedValues = @($state.Values)
    $savedUsbPowerValues = @($state.UsbPowerValues)
    if ([int]$state.SchemaVersion -ne 1 -or
        $savedValues.Count -eq 0 -or
        $savedValues.Count -ne [int]$sentinelTargetCount -or
        $savedUsbPowerValues.Count -eq 0 -or
        $savedUsbPowerValues.Count -ne [int]$sentinelUsbPowerTargetCount) {
        exit 1
    }

    foreach ($savedValue in $savedValues) {
        $rotation = Get-Hklm64Value -SubKey ([string]$savedValue.RegistrySubKey) -Name 'Rotation'
        if ($null -eq $rotation -or [int]$rotation -ne $expectedRotation) {
            exit 1
        }
    }

    foreach ($savedUsbPowerValue in $savedUsbPowerValues) {
        $enabled = Get-UsbPowerSettingEnabled `
            -SettingClass ([string]$savedUsbPowerValue.SettingClass) `
            -InstanceName ([string]$savedUsbPowerValue.InstanceName)
        if ($null -eq $enabled -or $enabled) {
            exit 1
        }
    }

    Write-Output "Detected: portrait rotation and USB 3.x power management configured (version $expectedVersion)."
    exit 0
}
catch {
    exit 1
}
