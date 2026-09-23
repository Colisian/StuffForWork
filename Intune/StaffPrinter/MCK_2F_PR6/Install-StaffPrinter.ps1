<#
.SYNOPSIS
    Installs a staff printer as a direct TCP/IP (port 9100) printer for all users.

.DESCRIPTION
    Reads the bundled printer.csv (Name, DriverName, PortAddress, Location, Comment) and:
      1. Ensures the printer driver is present. If it is not already installed (e.g. by the
         "Canon Generic Plus UFR II Driver" dependency app), installs any *.inf found under
         a bundled .\Driver\ folder with pnputil, then registers it with Add-PrinterDriver.
      2. Creates/repairs a Standard TCP/IP port pointing at the printer's DDNS hostname
         (<name>.resource.dyn.umd.edu).
      3. Creates the printer, or repairs it in place if it exists with the wrong driver/port.

    Runs as SYSTEM - the printer is machine-wide, so it shows up for every user who signs in.
    Works both as a command-line install (Method A) and pasted into Intune's Win32
    "PowerShell script installer" box (Method B); companion files are found via $ScriptDir.

    Exit codes: 0 success, 1 failure.

.PARAMETER CsvPath
    Path to printer.csv. Defaults to printer.csv next to the script (or in CWD when pasted).

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-StaffPrinter.ps1

.EXAMPLE
    .\Install-StaffPrinter.ps1 -WhatIf

.NOTES
    Author:  Oji (cmcleod1@umd.edu)
    Date:    2026-09-22
    Version: 1.0.0
    Log:     C:\ProgramData\StaffPrinters\<PrinterName>-Install.log
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$CsvPath
)

begin {
    $ErrorActionPreference = 'Stop'

    # Relaunch under 64-bit PowerShell if started from a 32-bit host - the PrintManagement
    # cmdlets and pnputil must run natively on 64-bit Windows.
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess -and $PSCommandPath) {
        $ps64 = Join-Path $env:WINDIR 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
        $relaunchArgs = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', $PSCommandPath)
        if ($CsvPath) { $relaunchArgs += @('-CsvPath', $CsvPath) }
        & $ps64 @relaunchArgs
        exit $LASTEXITCODE
    }

    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    if (-not $CsvPath) { $CsvPath = Join-Path $ScriptDir 'printer.csv' }

    $logDir = 'C:\ProgramData\StaffPrinters'
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force -WhatIf:$false | Out-Null }
}

process {
    $exitCode = 0
    $transcribing = $false
    try {
        $printer = Import-Csv -Path $CsvPath | Select-Object -First 1
        if (-not $printer.Name -or -not $printer.DriverName -or -not $printer.PortAddress) {
            throw "printer.csv must define Name, DriverName and PortAddress."
        }
        $name   = $printer.Name.Trim()
        $driver = $printer.DriverName.Trim()
        $fqdn   = $printer.PortAddress.Trim()
        $port   = "IP_$fqdn"

        try {
            Start-Transcript -Path (Join-Path $logDir "$name-Install.log") -Append -WhatIf:$false | Out-Null
            $transcribing = $true
        } catch { }

        Write-Output "[$name] Driver '$driver' -> port '$port' ($fqdn`:9100)"

        # Warn (don't fail) if DNS can't resolve yet - the port still works once DNS does.
        try {
            $ip = (Resolve-DnsName -Name $fqdn -Type A -ErrorAction Stop | Where-Object IPAddress |
                Select-Object -First 1).IPAddress
            Write-Output "DNS: $fqdn -> $ip"
        } catch {
            Write-Warning "DNS: $fqdn did not resolve from this device ($($_.Exception.Message))."
        }

        # --- 1. Driver ---------------------------------------------------------------
        # Retry - the spooler's CIM provider occasionally returns nothing on the first query
        $driverPresent = $false
        foreach ($attempt in 1..3) {
            if (Get-PrinterDriver -Name $driver -ErrorAction SilentlyContinue) { $driverPresent = $true; break }
            Start-Sleep -Seconds 2
        }
        if ($driverPresent) {
            Write-Output "Driver already installed."
        } else {
            $infs = Get-ChildItem -Path (Join-Path $ScriptDir 'Driver') -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue
            if (-not $infs) {
                throw "Driver '$driver' is not installed and no bundled .\Driver\*.inf was found. Deploy the driver app first (dependency) or bundle the driver."
            }
            foreach ($inf in $infs) {
                if ($PSCmdlet.ShouldProcess($inf.FullName, 'pnputil /add-driver /install')) {
                    Write-Output "pnputil /add-driver $($inf.FullName)"
                    & "$env:WINDIR\System32\pnputil.exe" /add-driver $inf.FullName /install | Out-Null
                    # 259 = ERROR_NO_MORE_ITEMS: package staged, no matching PnP device - expected for printers
                    if ($LASTEXITCODE -notin 0, 259, 3010) { Write-Warning "pnputil exit $LASTEXITCODE for $($inf.Name)" }
                }
            }
            if ($PSCmdlet.ShouldProcess($driver, 'Add-PrinterDriver')) {
                Add-PrinterDriver -Name $driver
            }
        }

        # --- 2. Port -----------------------------------------------------------------
        $existingPort = Get-PrinterPort -Name $port -ErrorAction SilentlyContinue
        if ($existingPort -and $existingPort.PrinterHostAddress -ne $fqdn) {
            # Wrong target - detach any printer using it, then rebuild the port
            Get-Printer | Where-Object PortName -EQ $port | ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_.Name, 'Remove-Printer (port being rebuilt)')) { Remove-Printer -Name $_.Name }
            }
            if ($PSCmdlet.ShouldProcess($port, 'Remove-PrinterPort')) { Remove-PrinterPort -Name $port }
            $existingPort = $null
        }
        if (-not $existingPort -and $PSCmdlet.ShouldProcess($port, "Add-PrinterPort -> $fqdn`:9100")) {
            Add-PrinterPort -Name $port -PrinterHostAddress $fqdn -PortNumber 9100
        }

        # --- 3. Printer --------------------------------------------------------------
        $printerArgs = @{
            Name       = $name
            DriverName = $driver
            PortName   = $port
            Location   = $printer.Location
            Comment    = $printer.Comment
        }
        $existing = Get-Printer -Name $name -ErrorAction SilentlyContinue
        if ($existing -and $existing.Type -ne 'Local') {
            throw "A non-local printer named '$name' exists (Type=$($existing.Type)). Remove it first."
        }
        if ($existing) {
            if ($PSCmdlet.ShouldProcess($name, 'Set-Printer (repair driver/port/location)')) {
                Set-Printer @printerArgs
            }
        } elseif ($PSCmdlet.ShouldProcess($name, 'Add-Printer')) {
            Add-Printer @printerArgs
        }

        # --- Verify ------------------------------------------------------------------
        if (-not $WhatIfPreference) {
            $check = Get-Printer -Name $name -ErrorAction SilentlyContinue
            if (-not $check -or $check.DriverName -ne $driver -or $check.PortName -ne $port) {
                throw "Verification failed for '$name'."
            }
            Write-Output "SUCCESS: '$name' installed (Driver=$($check.DriverName), Port=$($check.PortName))."
        }
    } catch {
        Write-Error "Install failed: $($_.Exception.Message)" -ErrorAction Continue
        $exitCode = 1
    } finally {
        if ($transcribing) { Stop-Transcript | Out-Null }
    }
    exit $exitCode
}
