<#
.SYNOPSIS
    Intune Win32 custom detection script for ArcGIS Drone2Map 2026.1.

.DESCRIPTION
    Reports the app as installed only when the UMD wrapper sentinel and the exact MSI
    ProductCode for ArcGIS Drone2Map 2026.1.0.1901 are both present. This prevents a
    partially completed MSI run or an unrelated Drone2Map version from satisfying detection.

    Intune Win32 custom detection contract:
        detected     = exit code 0 AND at least one line on STDOUT
        not detected = exit code 0 AND empty STDOUT

    Configure "Run script as 32-bit process on 64-bit clients" to No.

.NOTES
    Author  : Oji McLeod (cmcleod1@umd.edu) - ITFO / Digital Services & Technologies, UMD Libraries
    Date    : 2026-08-17
    Version : 1.0.0
    Stdout  : kept well under Intune's 2048-character limit
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    # Return not detected if the Intune detection rule was accidentally set to 32-bit.
    exit 0
}

$sentinelPath = 'HKLM:\SOFTWARE\UMD\Intune\ArcGISDrone2Map'
$expectedVersion = '2026.1.0.1901'
$expectedProductCode = '{E4CA5C88-DD5C-4686-8070-CF6CAC6B6FDA}'

if (-not (Test-Path -LiteralPath $sentinelPath)) {
    exit 0
}

$sentinel = Get-ItemProperty -LiteralPath $sentinelPath
if ($sentinel.PackageVersion -ne $expectedVersion -or
    $sentinel.ProductCode -ne $expectedProductCode) {
    exit 0
}

$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

foreach ($root in $uninstallRoots) {
    $productPath = Join-Path $root $expectedProductCode
    if (-not (Test-Path -LiteralPath $productPath)) { continue }

    $product = Get-ItemProperty -LiteralPath $productPath
    if ($product.DisplayName -like 'ArcGIS Drone2Map*') {
        Write-Output "Detected: ArcGIS Drone2Map $expectedVersion ($expectedProductCode)"
        exit 0
    }
}

# Empty stdout plus exit 0 tells Intune that the app is not installed.
exit 0
