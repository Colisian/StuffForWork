Start-Transcript -Path c:\windows\temp\printer_detection.log

#Define list of printers to detect - Update this with the names of your printers
$Printers = @(
                'EPSON TM-T20'
                'EPSON TM-T20II'

)

#Check every defined printer in the list to see if it's installed
$numberofprintersfound = 0
Write-Host ("[Detecting Installed Printers(s)]")  -ForegroundColor Cyan -BackgroundColor Black
foreach ($printer in $printers) {
    try {
        Get-Printer -Name $printer -ErrorAction Stop | Out-Null
        $numberofprintersfound++
    }
    catch {
        "- $($printer) was not found"
    }
}

#If all printers are installed, exit 0
if ($numberofprintersfound -eq $printers.count) {
    write-host ("[Found $numberofprintersfound/$($printers.count) Printers]")  -ForegroundColor Cyan -BackgroundColor Black
    exit 0
}
else {
    write-host ("[Found $numberofprintersfound/$($printers.count) Printers]")  -ForegroundColor Red -BackgroundColor Black
    exit 1
}
Stop-Transcript