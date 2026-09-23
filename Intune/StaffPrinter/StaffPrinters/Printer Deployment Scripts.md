# Printer Deployment Scripts

Below are the scripts required to create the Win32 app to install the printers. All of the files are [packaged here for your convenience](https://umd-dit.atlassian.net/wiki/download/attachments/45285395/printer_template.zip?api=v2). Alternatively, you can copy and paste the content from the sources below as you work through the process in the [Printer Deployment](https://umd-dit.atlassian.net/wiki/spaces/DMS/pages/45285395/Printer+Deployment) document. 

#### Add\_Printers.ps1

```
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
        PortName     = $Printer.Name
    }

    $PrinterPortOptions = @{
        ComputerName       = $env:COMPUTERNAME
        Name               = $Printer.Name
        PrinterHostAddress = $Printer.PortAddress
        PortNumber         = '9100'
    }

    #Remove Printer and PrinterPort if it already exists 
    if (Get-PrinterPort -ComputerName $env:COMPUTERNAME | Where-Object Name -EQ $printer.Name) {  
        Write-Warning ("Port for Printer {0} already exists, removing existing port and printer first" -f $printer.Name)
        Remove-Printer -Name $printer.Name -ComputerName $env:COMPUTERNAME -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 10
        Remove-PrinterPort -Name $printer.Name -ComputerName $env:COMPUTERNAME -Confirm:$false
    }

    #Add Printer and PrinterPort
    Add-PrinterPort @PrinterPortOptions
    Add-Printer @PrinterAddOptions -ErrorAction SilentlyContinue
    $currentnumber++
}
Stop-Transcript
```

#### Detection.ps1

```
Start-Transcript -Path c:\windows\temp\printer_detection.log

#Define list of printers to detect - Update this with the names of your printers
$Printers = @(
                'Multi-Printy-C360i'
                'Multi-Printy-C3658'
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
```

#### Remove\_Printers.ps1

```
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
```

#### Install.cmd

```
powershell.exe -executionpolicy bypass -file .\add_printers.ps1
```

#### Uninstall.cmd

```
powershell.exe -executionpolicy bypass -file .\remove_printers.ps1
```
