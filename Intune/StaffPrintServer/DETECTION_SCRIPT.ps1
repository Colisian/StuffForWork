<#
.SYNOPSIS
    Detection script for staff printer installations.

.DESCRIPTION
    Detects whether all or any staff printers are installed and available on the system.
    Used by Intune to determine if an app/script needs to be deployed or updated.
    Returns exit code 0 if required printers are installed, 1 if not found.

.NOTES
    Print Server: LIBRPS403v.ad.umd.edu
    Designed for Intune detection scripts
#>

# Parameters - All Staff Printers
$PrinterNames = @(
    "EPL_1F_PR1",
    "HBK_1F_PR2",
    "HBK_2F_PR1",
    "HBK_2F_PR3",
    "HBK_3F_PR1",
    "HBK_4F_PR1",
    "MCK_1F_PR2",
    "MCK_1F_PR3",
    "MCK_1F_PR4",
    "MCK_2F_PR2",
    "MCK_2F_PR6",
    "MCK_3F_PR1",
    "MCK_4F_PR1",
    "MCK_4F_PR2",
    "MCK_4F_PR3",
    "MCK_5F_PR1",
    "MCK_6F_PR1",
    "MCK_6F_PR2",
    "MCK_6F_PR4",
    "MCK_7F_PR1",
    "MCK_BF_PR2",
    "MCK_BF_PR3",
    "MCK_BF_PR5",
    "PAL_1F_PR1",
    "PAL_1F_PR2",
    "PAL_2F_PR1",
    "SVN_1F_PR2"
)

$PrintServer = "LIBRPS403v.ad.umd.edu"
$installedPrinters = @()
$missingPrinters = @()

Write-Host "Detecting staff printer installations..."

foreach ($PrinterName in $PrinterNames) {
    try {
        # Check if printer exists by short name
        $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue

        # Also check for full UNC path format
        if (-not $printer) {
            $uncPath = "\\$PrintServer\$PrinterName"
            $printer = Get-Printer -Name $uncPath -ErrorAction SilentlyContinue
        }

        if ($printer) {
            $printerStatus = $printer.PrinterStatus
            Write-Host " Found '$PrinterName' - Status: $printerStatus"
            $installedPrinters += $PrinterName
        } else {
            Write-Host " Missing '$PrinterName'"
            $missingPrinters += $PrinterName
        }

    } catch {
        Write-Warning " Error detecting '$PrinterName': $($_.Exception.Message)"
        $missingPrinters += $PrinterName
    }
}

Write-Host ""
Write-Host "Detection Summary:"
Write-Host "  Installed: $($installedPrinters.Count) / $($PrinterNames.Count)"
Write-Host "  Missing:   $($missingPrinters.Count) / $($PrinterNames.Count)"

if ($missingPrinters.Count -gt 0) {
    Write-Host ""
    Write-Host "Missing printers: $($missingPrinters -join ', ')"
    # Exit 1 indicates printers are not installed (trigger remediation)
    exit 1
} else {
    Write-Host ""
    Write-Host "All printers detected successfully."
    # Exit 0 indicates all required printers are installed (no action needed)
    exit 0
}
