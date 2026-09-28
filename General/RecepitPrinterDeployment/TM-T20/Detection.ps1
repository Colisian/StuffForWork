<#
.SYNOPSIS
    Detects if the Epson TM-T20II printer is installed.
.DESCRIPTION
    Intune detection script. Checks for the auto-created printer
    on the Dynamic Print Monitor USB port. Returns exit 0 if found.
.NOTES
    Author: Oji
    Date: 2026-02-10
    Version: 2.0
#>

Start-Transcript -Path c:\windows\temp\printer_detection.log

$PrinterName = 'EPSON TM-T20II Receipt5'

Write-Host ("[Detecting Installed Printer]") -ForegroundColor Cyan -BackgroundColor Black
try {
    $printer = Get-Printer -Name $PrinterName -ErrorAction Stop
    Write-Host ("Found: {0} on port {1}" -f $printer.Name, $printer.PortName) -ForegroundColor Green
    Stop-Transcript
    exit 0
}
catch {
    Write-Host ("Printer '{0}' was not found" -f $PrinterName) -ForegroundColor Red
    Stop-Transcript
    exit 1
}
