<#
.SYNOPSIS
    Detection script for SVN_1F_PR2 printer.

.DESCRIPTION
    Detects whether the SVN_1F_PR2 printer is installed and available on the system.
    Used by Intune to determine if the printer needs to be deployed.
    Returns exit code 0 if printer is installed, 1 if not found.

.NOTES
    Printer Name: SVN_1F_PR2
    Print Server: LIBRPS403v.ad.umd.edu
#>

$PrinterName = "SVN_1F_PR2"
$PrintServer = "LIBRPS403v.ad.umd.edu"

try {
    # Check if printer exists by short name
    $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue

    # Also check for full UNC path format
    if (-not $printer) {
        $uncPath = "\\$PrintServer\$PrinterName"
        $printer = Get-Printer -Name $uncPath -ErrorAction SilentlyContinue
    }

    if ($printer) {
        Write-Host "SUCCESS: Printer '$PrinterName' is installed (Status: $($printer.PrinterStatus))"
        exit 0  # Detected
    } else {
        Write-Host "NOT FOUND: Printer '$PrinterName' is not installed"
        exit 1  # Not detected
    }
} catch {
    Write-Host "ERROR: Failed to detect printer '$PrinterName': $($_.Exception.Message)"
    exit 1  # Not detected
}
