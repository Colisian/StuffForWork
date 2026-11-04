<#
.SYNOPSIS
    Intune detection for the HP Universal Printing PCL 6 driver app.

.DESCRIPTION
    Detected only when 'HP Universal Printing PCL 6' is registered with the spooler at version
    61.360.1.26819 or newer. Reads the live driver version (not a registry marker), so a PC that
    already has an OLDER same-name driver - e.g. pulled down by print-server connections -
    is NOT detected and the driver app runs to upgrade it.
    Upload as the custom detection script (runs as SYSTEM). Exit 0 + stdout = detected.
    When you package a newer driver, raise $MinimumVersion to its DriverVer.

.NOTES
    Author:  Oji (cmcleod1@umd.edu)
    Date:    2026-11-04
    Version: 1.2.0
#>
$DriverName     = 'HP Universal Printing PCL 6'
$MinimumVersion = [version]'61.360.1.26819'   # DriverVer of hpcu360u.inf in this package

try {
    $v = [uint64](Get-PrinterDriver -Name $DriverName -ErrorAction Stop | Select-Object -First 1).DriverVersion
    $installed = [version]('{0}.{1}.{2}.{3}' -f ($v -shr 48), (($v -shr 32) -band 0xFFFF), (($v -shr 16) -band 0xFFFF), ($v -band 0xFFFF))
    if ($installed -ge $MinimumVersion) {
        Write-Output "DETECTED: $DriverName $installed"
        exit 0
    }
    exit 1
} catch {
    exit 1
}
