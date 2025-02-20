Start-Transcript -Path c:\windows\temp\printer_remove.log

#Read printers.csv as input
# cd "C:\Users\preeyen\Downloads\printer_template"    <- When testing locally uncomment this line and update the location to where your folder lives..
$Printers = Import-Csv ".\printers.csv"

#Loop through all printers in the csv-file and remove the Printer Port and Printer
$totalnumberofprinters = $Printers.Count
$currentnumber = 1
Write-Host ("`n[Remove Printer(s) from Windows]")  -ForegroundColor Cyan -BackgroundColor Black
foreach ($printer in $printers) {
    Write-Host ("[{0}/{1}] Removing Printer: {2}" -f $currentnumber, $totalnumberofprinters, $printer.Name) -ForegroundColor Cyan -BackgroundColor Black
    #Set options
    $PrinterRemoveOptions = @{
        Confirm = $false
        Name    = $Printer.Name
    }

    $PrinterPortRemoveOptions = @{
        Confirm      = $false
        Computername = $env:COMPUTERNAME
        Name         = $Printer.Name
    }

    #Remove printers and their ports
    Remove-Printer @PrinterRemoveOptions
    Start-Sleep -Seconds 10
    Remove-PrinterPort @PrinterPortRemoveOptions
}

#Remove the Printer Drivers
$totalnumberofdrivers = ($printers.drivername | Select-Object -Unique).count
$currentnumber = 1
Write-Host ("`n[Remove Printer Driver(s) from Windows]")  -ForegroundColor Cyan -BackgroundColor Black
foreach ($driver in $printers.drivername | Select-Object -Unique) {
    Write-Host ("[{0}/{1}] Removing Printer Driver: {2}" -f $currentnumber, $totalnumberofdrivers, $driver) -ForegroundColor Cyan -BackgroundColor Black
    $PrinterDriverRemoveOptions = @{
        Confirm               = $false
        Computername          = $env:COMPUTERNAME
        Name                  = $driver
    }
    Remove-PrinterDriver @PrinterDriverRemoveOptions
}

#Get all the Printer Drivers by scanning for the .inf files and uninstalling them using the pnputil.exe
$infs = get-childitem -Path . -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Fullname
$totalnumberofinfs = $infs.Count
$currentnumber = 1
Write-Host ("`n[Uninstall Printer Driver(s)]")  -ForegroundColor Cyan -BackgroundColor Black
Foreach ($inf in $infs) {
    Write-Host ("[{0}/{1}] Removing inf file {2}" -f $currentnumber, $totalnumberofinfs, $inf) -ForegroundColor Cyan -BackgroundColor Black
    try {
        c:\windows\sysnative\Pnputil.exe /d $inf /uninstall | Out-Null
    }
    catch {
        try {
            c:\windows\system32\Pnputil.exe /d $inf /uninstall | Out-Null
        }
        catch {
            C:\Windows\SysWOW64\pnputil.exe /d $inf /uninstall | Out-Null
        }
    }
    $currentnumber++
}
Stop-Transcript