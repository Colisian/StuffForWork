<#
.SYNOPSIS
    Removes network printers from the system.

.DESCRIPTION
    Removes specified network printers installed from the print server.
    Intended for deployment via Intune Company Portal or other automation tools.
    Use the same script for all printer uninstallation packages.

.NOTES
    Print Server: LIBRPS403v.ad.umd.edu
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
$failedRemovals = @()

Write-Host "Starting printer uninstallation process..."

foreach ($PrinterName in $PrinterNames) {
    try {
        # Check if printer exists by short name
        $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue

        # Also check for full UNC path format
        $printerToRemove = $printer
        if (-not $printerToRemove) {
            $uncPath = "\\$PrintServer\$PrinterName"
            $printerToRemove = Get-Printer -Name $uncPath -ErrorAction SilentlyContinue
        }

        if ($printerToRemove) {
            Write-Host "Removing printer '$PrinterName'..."
            Remove-Printer -Name $printerToRemove.Name -Confirm:$false
            Start-Sleep -Seconds 1

            # Verify removal - check both naming formats
            $verifyPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
            if (-not $verifyPrinter) {
                $uncPath = "\\$PrintServer\$PrinterName"
                $verifyPrinter = Get-Printer -Name $uncPath -ErrorAction SilentlyContinue
            }

            if (-not $verifyPrinter) {
                Write-Host " Successfully removed '$PrinterName'."
            } else {
                Write-Warning " Printer '$PrinterName' still exists after removal attempt."
                $failedRemovals += $PrinterName
            }
        } else {
            Write-Host "  - Printer '$PrinterName' is not installed. Skipping."
        }

    } catch {
        Write-Error "  ✗ Failed to remove printer '$PrinterName': $($_.Exception.Message)"
        $failedRemovals += $PrinterName
    }
}

Write-Host ""
if ($failedRemovals.Count -eq 0) {
    Write-Host "All printers removed successfully."
    exit 0
} else {
    Write-Host "Uninstallation completed with errors."
    Write-Error "Failed to remove the following printers: $($failedRemovals -join ', ')"
    exit 1
}
