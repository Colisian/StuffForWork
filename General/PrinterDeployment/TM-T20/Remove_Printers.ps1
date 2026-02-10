<#
.SYNOPSIS
    Removes the Epson TM-T20II printer driver from the Windows driver store.
.DESCRIPTION
    Uninstalls the Epson TM-T20II driver. The auto-created printer and USB port
    are managed by the Dynamic Print Monitor and will be cleaned up when the
    driver is removed and the printer is disconnected.
.NOTES
    Author: Oji
    Date: 2026-02-10
    Version: 2.0
#>

Start-Transcript -Path c:\windows\temp\printer_remove.log

$DriverName = "EPSON TM-T20II Receipt5"
$PrinterName = "EPSON TM-T20II Receipt5"

# Remove the auto-created printer if it exists
Write-Host ("[Remove Printer from Windows]") -ForegroundColor Cyan -BackgroundColor Black
try {
    Remove-Printer -Name $PrinterName -Confirm:$false -ErrorAction Stop
    Write-Host ("Removed printer: {0}" -f $PrinterName) -ForegroundColor Green
    Start-Sleep -Seconds 5
}
catch {
    Write-Host ("Printer '{0}' not found or already removed" -f $PrinterName) -ForegroundColor Yellow
}

# Remove the printer driver from Windows
Write-Host ("`n[Remove Printer Driver from Windows]") -ForegroundColor Cyan -BackgroundColor Black
try {
    Remove-PrinterDriver -Name $DriverName -Confirm:$false -ErrorAction Stop
    Write-Host ("Removed driver: {0}" -f $DriverName) -ForegroundColor Green
}
catch {
    Write-Host ("Driver '{0}' not found or already removed" -f $DriverName) -ForegroundColor Yellow
}

# Remove INF files from the driver store using pnputil
$infs = Get-ChildItem -Path . -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
Write-Host ("`n[Uninstall Printer Driver from Driver Store]") -ForegroundColor Cyan -BackgroundColor Black

# Find the published OEM INF name for removal
$oemInfs = pnputil.exe /enum-drivers | Select-String -Pattern "EA5INSTMT20II" -Context 3,0
if ($oemInfs) {
    $oemInfName = ($oemInfs.Context.PreContext | Select-String -Pattern "oem\d+\.inf").Matches.Value
    if ($oemInfName) {
        Write-Host ("Removing staged driver: {0}" -f $oemInfName) -ForegroundColor Cyan
        try {
            pnputil.exe /delete-driver $oemInfName /uninstall /force | Out-Null
            Write-Host ("Driver removed from store") -ForegroundColor Green
        }
        catch {
            Write-Host ("Failed to remove driver from store: {0}" -f $_) -ForegroundColor Red
        }
    }
}
else {
    Write-Host ("No staged Epson TM-T20II driver found in driver store") -ForegroundColor Yellow
}

Stop-Transcript
