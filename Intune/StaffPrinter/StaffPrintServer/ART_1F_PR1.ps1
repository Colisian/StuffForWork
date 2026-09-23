<#
.SYNOPSIS
    Reinstalls network printer from print server, using full UNC path to avoid cached driver issues.

.DESCRIPTION
    Removes existing printer if found, then reconnects using the full path. Includes optional driver cache cleanup.
    Intended for deployment via Intune Company Portal or other automation tools.
    IMPORTANT: Add-Printer -ConnectionName creates a per-user printer connection.
    Deploy this app in USER context (not SYSTEM).

.NOTES
    Printer: ART_1F_PR1
    Print Server: LIBRPS403v.ad.umd.edu

    INTUNE DEPLOYMENT COMMANDS (Copy & Paste):
    Install Command (assign in USER context):
    powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File .\ART_1F_PR1.ps1

    Uninstall Command:
    powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File .\UNINSTALL_TEMPLATE.ps1

    Detection Script:
    Use DetectionScripts\ART_1F_PR1_Detection.ps1 (per-printer).
    Do NOT use the shared DETECTION_SCRIPT.ps1 here - it succeeds if ANY staff printer
    is present, which would mark this app as installed when other printers exist.
#>

# Parameters
$PrinterName     = "ART_1F_PR1"
$PrintServer     = "LIBRPS403v.ad.umd.edu"
$PrinterPath     = "\\$PrintServer\$PrinterName"

# Logging (best effort - never fail the install because logging failed)
$transcribing = $false
try {
    $logDir = 'C:\ProgramData\StaffPrinters'
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
    Start-Transcript -Path (Join-Path $logDir "$PrinterName-$env:USERNAME.log") -Append -ErrorAction Stop | Out-Null
    $transcribing = $true
} catch { }

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
    # Remove existing printer if present - check both short name and UNC connection name
    foreach ($name in @($PrinterName, $PrinterPath)) {
        $existingPrinter = Get-Printer -Name $name -ErrorAction SilentlyContinue
        if ($existingPrinter) {
            Write-Host "Removing existing printer '$($existingPrinter.Name)'..."
            Remove-Printer -Name $existingPrinter.Name -Confirm:$false
            Start-Sleep -Seconds 1
        }
    }

    Write-Host "Adding printer using full UNC path: $PrinterPath"
    Add-Printer -ConnectionName $PrinterPath

    Start-Sleep -Seconds 3

    # Verify - printer connections are usually named by their full UNC path
    $addedPrinter = Get-Printer -Name $PrinterPath -ErrorAction SilentlyContinue
    if (-not $addedPrinter) {
        $addedPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    }

    if ($addedPrinter) {
        Write-Host "Successfully added printer '$($addedPrinter.Name)'."
        Write-Host "    Status: $($addedPrinter.PrinterStatus)"
        Write-Host "    Driver: $($addedPrinter.DriverName)"
    } else {
        Write-Error "Printer '$PrinterName' was added, but could not be verified."
        if ($transcribing) { Stop-Transcript | Out-Null }
        exit 1
    }

} catch {
    Write-Error "Failed to add printer '$PrinterName': $($_.Exception.Message)"
    if ($transcribing) { Stop-Transcript | Out-Null }
    exit 1
}

Write-Host "`n If you experience issues printing, please restart your computer."
Write-Host "Script completed."
if ($transcribing) { Stop-Transcript | Out-Null }
exit 0