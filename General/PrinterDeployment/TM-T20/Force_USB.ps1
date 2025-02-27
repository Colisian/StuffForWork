#Forces USB printer installation

$targetPrinterName = 'EPSON TM-T20II'
$targetPrinterPort = 'USB001'

try {
    #Attempt to retrieve printe
    $printer = Get-Printer -Name $targetPrinterName -ErrorAction Stop
    Write-Host "Found printer '$targetPrinterName' with current port '$($printer.PortName)'."

    #If the printer is already installed with the correct port
    if ($printer.PortName -ne $targetPrinterPort) {
        Write-Host "Updating printer '$targetPrinterName' to use port '$desiredPort'."
        Set-Printer -Name $targetPrinterName -PortName $desiredPort -ErrorAction Stop
        Write-Host "Successfully updated printer '$targetPrinterName' to use port '$desiredPort'."

    }
    else {
        Write-Host "Printer '$targetPrinterName' is already installed with the correct port."
    }
}
catch {
    Write-Host "Error: Unable to update printer '$targetPrinterName'. It may not be installed or an error occurred."
}