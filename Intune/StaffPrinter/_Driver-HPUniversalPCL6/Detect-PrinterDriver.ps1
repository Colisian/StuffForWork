<#
.SYNOPSIS
    Intune detection for the HP Universal Printing PCL 6 driver app.

.DESCRIPTION
    Detected when the print driver is registered with the spooler. Upload as the custom
    detection script (runs as SYSTEM). Exit 0 + stdout = detected, exit 1 = not detected.
    To force an upgrade to a newer driver later, set $MinimumVersion and redeploy.

.NOTES
    Author:  Oji (cmcleod1@umd.edu)
    Date:    2026-09-22
    Version: 1.0.0
#>
$DriverName     = 'HP Universal Printing PCL 6'
$MinimumVersion = $null   # e.g. [version]'3.20.0.0' once you know the packaged version

try {
    $null = Get-PrinterDriver -Name $DriverName -ErrorAction Stop
    if ($MinimumVersion) {
        $recorded = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\UMDLibraries\StaffPrinters\Driver' -ErrorAction Stop).Version
        if ([version]$recorded -lt $MinimumVersion) { exit 1 }
    }
    Write-Output "DETECTED: $DriverName"
    exit 0
} catch {
    exit 1
}
