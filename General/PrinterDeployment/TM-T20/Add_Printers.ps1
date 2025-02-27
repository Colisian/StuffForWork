Start-Transcript -Path c:\windows\temp\printer_install.log

#Read printers.csv as input
# cd "C:\Users\preeyen\Downloads\printer_template"
# ^^^^ When testing locally uncomment the above line and update the location to where your folder lives.
$Printers = Import-Csv ".\printers.csv"

#Add all Printer Drivers by scanning for the .inf files and installing them using the pnputil.exe
$infs = get-childitem -Path . -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Fullname
$totalnumberofinfs = $infs.Count
$currentnumber = 1
Write-Host ("[Install Printer Driver(s)]")  -ForegroundColor Cyan -BackgroundColor Black
Foreach ($inf in $infs) {
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

#Add all installed Drivers to Windows using the csv-file for the correct names
$totalnumberofdrivers = ($printers.drivername | Select-Object -Unique).count
$currentnumber = 1
Write-Host ("`n[Add Printer Driver(s) to Windows]")  -ForegroundColor Cyan -BackgroundColor Black
foreach ($driver in $printers.drivername | Select-Object -Unique) {
    Write-Host ("[{0}/{1}] Adding Printer Driver: {2}" -f $currentnumber, $totalnumberofdrivers, $driver) -ForegroundColor Cyan -BackgroundColor Black
    Add-PrinterDriver -Name $driver
    $currentnumber++
}

#Loop through all printers in the csv-file and add the PrinterPort and Printer
$totalnumberofprinters = $Printers.Count
$currentnumber = 1
Write-Host ("`n[Add Printer(s) to Windows]")  -ForegroundColor Cyan -BackgroundColor Black
foreach ($printer in $printers) {
    Write-Host ("[{0}/{1}] Adding Printer: {2}" -f $currentnumber, $totalnumberofprinters, $printer.Name) -ForegroundColor Cyan -BackgroundColor Black
    #Set options for adding printers and their ports
    $PrinterAddOptions = @{
        ComputerName = $env:COMPUTERNAME
        Comment      = $Printer.Comment
        DriverName   = $Printer.DriverName
        Location     = $Printer.Location
        Name         = $Printer.Name
        PortName     = "USB001"
    }

    $PrinterPortOptions = @{
        ComputerName       = $env:COMPUTERNAME
        Name               = "USB001"
    }


    #Remove Printer and PrinterPort if it already exists 
    if (Get-PrinterPort -ComputerName $env:COMPUTERNAME | Where-Object Name -EQ "USB001") {  
        Write-Warning ("Port for Printer {0} already exists, removing existing port and printer first" -f $printer.Name)
        Remove-Printer -Name $printer.Name -ComputerName $env:COMPUTERNAME -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 10
        Remove-PrinterPort -Name "USB001" -ComputerName $env:COMPUTERNAME -Confirm:$false
    }

    #Add Printer and PrinterPort
    Add-PrinterPort @PrinterPortOptions
    Add-Printer @PrinterAddOptions -ErrorAction SilentlyContinue
    $currentnumber++
}
Stop-Transcript