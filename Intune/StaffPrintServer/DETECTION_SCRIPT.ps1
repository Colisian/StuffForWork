<#
.SYNOPSIS
    Detection script for staff printer installations.

.DESCRIPTION
    Detects whether ANY staff printer is installed and available on the system.
    Returns exit code 0 if at least one staff printer is installed, 1 if none found.

    WARNING: Do NOT use this as the detection script for a single-printer Win32 app -
    it exits 0 when ANY staff printer is present, so Intune would mark the app installed
    even if that app's specific printer is missing. Use the per-printer scripts in
    DetectionScripts\ instead. This script is only appropriate for an "all staff
    printers" bundle app paired with UNINSTALL_TEMPLATE.ps1.

    NOTE: Win32 app detection scripts run as SYSTEM, which cannot see per-user printer
    connections created by Add-Printer -ConnectionName. Verify detection behavior on a
    test device before relying on Get-Printer-based detection.

.NOTES
    Print Server: LIBRPS403v.ad.umd.edu
    Designed for Intune detection scripts
#>

# Parameters - All Staff Printers
$PrinterNames = @(
    "ARCH_1F_PR2",
    "ART_1F_PR1",
    "EPL_1F_PR1",
    "HBK_1F_PR1",
    "HBK_1F_PR2",
    "HBK_2F_PR1",
    "HBK_2F_PR3",
    "HBK_3F_PR1",
    "HBK_4F_PR1",
    "HBK_4F_PR2",
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
    "STM_1F_CIRC",
    "SVN_1F_PR2"
)

$PrintServer = "LIBRPS403v.ad.umd.edu"
$installedPrinters = @()
$missingPrinters = @()

# Note: keep stdout compact - Intune detection/remediation output should stay under 2048 chars
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
            $installedPrinters += $PrinterName
        } else {
            $missingPrinters += $PrinterName
        }

    } catch {
        $missingPrinters += $PrinterName
    }
}

# Check if at least ONE printer is installed
if ($installedPrinters.Count -gt 0) {
    Write-Host "SUCCESS: $($installedPrinters.Count)/$($PrinterNames.Count) staff printers detected: $($installedPrinters -join ', ')"
    # Exit 0 indicates printer(s) are installed (no action needed)
    exit 0
} else {
    Write-Host "FAILED: No staff printers found (0/$($PrinterNames.Count))"
    # Exit 1 indicates no printers are installed (trigger installation)
    exit 1
}
