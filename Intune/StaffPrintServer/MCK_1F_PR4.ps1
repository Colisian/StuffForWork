<#
.SYNOPSIS
    Reinstalls network printer from print server, using full UNC path to avoid cached driver issues.

.DESCRIPTION
    Removes existing printer if found, then reconnects using the full path. Includes optional driver cache cleanup.
    Intended for deployment via Intune Company Portal or other automation tools.

.NOTES
    Printer: MCK_1F_PR4
    Print Server: LIBRPS403v.ad.umd.edu
#>

# Parameters
$PrinterName     = "MCK_1F_PR4"
$PrintServer     = "LIBRPS403v.ad.umd.edu"
$PrinterPath     = "\\$PrintServer\$PrinterName"

# Optional: Clear driver cache - ONLY if you're experiencing persistent driver issues
# Uncomment these lines if needed
<# 
Write-Host "Stopping Print Spooler..."
Stop-Service spooler -Force

Write-Host "Clearing cached print drivers..."
$driverPath = "C:\Windows\System32\spool\drivers\x64\3\"
if (Test-Path $driverPath) {
    Remove-Item "$driverPath*" -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Starting Print Spooler..."
Start-Service spooler
Start-Sleep -Seconds 2
#>

try {
    # Remove existing printer if present
    $existingPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if ($existingPrinter) {
        Write-Host "Removing existing printer '$PrinterName'..."
        Remove-Printer -Name $PrinterName -Confirm:$false
        Start-Sleep -Seconds 1
    }

    Write-Host "Adding printer using full UNC path: $PrinterPath"
    Add-Printer -ConnectionName $PrinterPath

    Start-Sleep -Seconds 3

    $addedPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if ($addedPrinter) {
        Write-Host "Successfully added printer '$PrinterName'."
        Write-Host "    Status: $($addedPrinter.PrinterStatus)"
        Write-Host "    Driver: $($addedPrinter.DriverName)"
    } else {
        Write-Warning " Printer '$PrinterName' was added, but could not be verified."
    }

} catch {
    Write-Error "Failed to add printer '$PrinterName': $($_.Exception.Message)"
    exit 1
}

Write-Host "`n If you experience issues printing, please restart your computer."
Write-Host "Script completed."
