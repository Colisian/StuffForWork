<#
.SYNOPSIS
    Stages Epson TM-T20II driver for USB printer auto-detection.
.DESCRIPTION
    Installs the Epson TM-T20II INF driver into the Windows driver store via pnputil
    and registers the printer driver with Windows. The printer and USB port are
    auto-created by the Dynamic Print Monitor when the printer is physically connected.
    Do NOT manually create USB ports - this conflicts with the Epson driver.
.NOTES
    Author: Oji
    Date: 2026-02-10
    Version: 2.0
#>

Start-Transcript -Path c:\windows\temp\printer_install.log

$DriverName = "EPSON TM-T20II Receipt5"

# Stage all INF files into the Windows driver store using pnputil
$infs = Get-ChildItem -Path . -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
$totalnumberofinfs = $infs.Count
$currentnumber = 1
Write-Host ("[Install Printer Driver(s)]") -ForegroundColor Cyan -BackgroundColor Black
foreach ($inf in $infs) {
    Write-Host ("[{0}/{1}] Adding INF File: {2}" -f $currentnumber, $totalnumberofinfs, $inf) -ForegroundColor Cyan -BackgroundColor Black
    try {
        c:\windows\sysnative\Pnputil.exe /a $inf | Out-Null
    }
    catch {
        try {
            c:\windows\system32\Pnputil.exe /a $inf | Out-Null
        }
        catch {
            C:\Windows\SysWOW64\pnputil.exe /a $inf | Out-Null
        }
    }
    $currentnumber++
}

# Register the printer driver with Windows
Write-Host ("`n[Add Printer Driver to Windows]") -ForegroundColor Cyan -BackgroundColor Black
Write-Host ("Adding Printer Driver: {0}" -f $DriverName) -ForegroundColor Cyan -BackgroundColor Black
try {
    Add-PrinterDriver -Name $DriverName -ErrorAction Stop
    Write-Host ("Driver registered successfully") -ForegroundColor Green
}
catch {
    Write-Error ("Failed to register driver: {0}" -f $_)
    Stop-Transcript
    exit 1
}

# USB port and printer are auto-created by the Dynamic Print Monitor
# when the printer is physically connected via USB. No manual port/printer creation needed.
Write-Host ("`n[Driver staging complete]") -ForegroundColor Green -BackgroundColor Black
Write-Host ("The printer will appear automatically when connected via USB.") -ForegroundColor Cyan

Stop-Transcript