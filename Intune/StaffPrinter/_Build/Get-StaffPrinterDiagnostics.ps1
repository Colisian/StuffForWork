<#
.SYNOPSIS
    Read-only diagnostics for a direct-IP staff printer that installs but won't print.

.DESCRIPTION
    Collects what's needed to explain spooler errors such as 0x000000CB
    ("The system could not find the environment option that was entered"):
      - The printer's driver, port, print processor and datatype
      - Every installed version of that driver, and the print processor it expects
      - Whether that print processor is actually registered with the spooler
      - Print-server connections that use the same driver name (version mixing)
      - Windows Protected Print Mode policy (blocks third-party drivers)
      - DNS + TCP 9100 to the printer
      - Recent PrintService errors and the StaffPrinters install logs
    Changes nothing. Run elevated for full event-log access.

.PARAMETER PrinterName
    Default: MCK_6F_PR4

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Get-StaffPrinterDiagnostics.ps1 -PrinterName MCK_6F_PR4

.NOTES
    Author:  Oji (cmcleod1@umd.edu)
    Date:    2026-11-04
    Version: 1.0.0
    Output:  C:\ProgramData\StaffPrinters\Diag-<PrinterName>-<timestamp>.txt
#>
[CmdletBinding()]
param(
    [string]$PrinterName = 'MCK_6F_PR4'
)

begin {
    $ErrorActionPreference = 'Continue'
    $outDir = 'C:\ProgramData\StaffPrinters'
    if (-not (Test-Path $outDir)) { New-Item -Path $outDir -ItemType Directory -Force | Out-Null }
    $outFile = Join-Path $outDir ("Diag-{0}-{1}.txt" -f $PrinterName, (Get-Date -Format 'yyyyMMdd-HHmmss'))

    function Format-DriverVersion {
        [CmdletBinding()]
        param([uint64]$Value)
        '{0}.{1}.{2}.{3}' -f ($Value -shr 48), (($Value -shr 32) -band 0xFFFF), (($Value -shr 16) -band 0xFFFF), ($Value -band 0xFFFF)
    }
}

end {
    $report = & {
        "=== $PrinterName diagnostics on $env:COMPUTERNAME - $(Get-Date) ==="
        "OS: $((Get-CimInstance Win32_OperatingSystem).Caption) build $([Environment]::OSVersion.Version)"
        "Spooler: $((Get-Service Spooler).Status)"

        "`n--- Printer ---"
        $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
        if (-not $printer) { "Printer '$PrinterName' NOT FOUND"; return }
        $printer | Format-List Name, Type, DriverName, PortName, PrintProcessor, Datatype, PrinterStatus, JobCount | Out-String

        "--- Port ---"
        $port = Get-PrinterPort -Name $printer.PortName -ErrorAction SilentlyContinue
        $port | Format-List Name, PrinterHostAddress, PortNumber, Protocol, SNMPEnabled | Out-String
        if ($port.PrinterHostAddress -as [ipaddress]) {
            "Port targets a raw IP (not a DDNS name)"
            "TCP 9100 open: $((Test-NetConnection $port.PrinterHostAddress -Port 9100 -WarningAction SilentlyContinue).TcpTestSucceeded)"
        } elseif ($port.PrinterHostAddress) {
            try {
                $ip = (Resolve-DnsName $port.PrinterHostAddress -Type A -ErrorAction Stop | Where-Object IPAddress).IPAddress -join ';'
                "DNS: $($port.PrinterHostAddress) -> $ip"
                "TCP 9100 open: $((Test-NetConnection $port.PrinterHostAddress -Port 9100 -WarningAction SilentlyContinue).TcpTestSucceeded)"
            } catch { "DNS: $($port.PrinterHostAddress) DOES NOT RESOLVE - jobs cannot reach the device" }
        }

        "`n--- Installed driver(s) named '$($printer.DriverName)' ---"
        Get-PrinterDriver -Name $printer.DriverName -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                Environment    = $_.PrinterEnvironment
                Version        = Format-DriverVersion $_.DriverVersion
                PrintProcessor = $_.PrintProcessor
                InfPath        = $_.InfPath
            }
        } | Format-List | Out-String
        "Driver store packages for this INF:"
        $infLeaf = Split-Path (Get-PrinterDriver -Name $printer.DriverName -ErrorAction SilentlyContinue | Select-Object -First 1).InfPath -Leaf
        Get-ChildItem "$env:WINDIR\System32\DriverStore\FileRepository" -Directory -Filter "$($infLeaf)_*" -ErrorAction SilentlyContinue |
            ForEach-Object { "  $($_.Name)  ($($_.LastWriteTime))" }

        "`n--- Print processors registered (Windows x64) ---"
        $procKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows x64\Print Processors'
        $procs = Get-ChildItem $procKey -ErrorAction SilentlyContinue
        foreach ($proc in $procs) {
            $dll = (Get-ItemProperty $proc.PSPath).Driver
            $dllPath = Join-Path "$env:WINDIR\System32\spool\prtprocs\x64" $dll
            "  {0,-12} {1,-20} present={2}" -f $proc.PSChildName, $dll, (Test-Path $dllPath)
        }
        if ($printer.PrintProcessor -notin $procs.PSChildName) {
            "  !! Printer uses print processor '$($printer.PrintProcessor)' which is NOT registered -> classic cause of 0x000000CB"
        }

        "`n--- Other queues using the same driver (version mixing) ---"
        Get-Printer | Where-Object { $_.DriverName -eq $printer.DriverName -and $_.Name -ne $PrinterName } |
            Format-Table Name, Type, PortName -AutoSize | Out-String

        "--- Windows Protected Print Mode ---"
        $wpp = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP' -ErrorAction SilentlyContinue
        "WindowsProtectedPrintGroupPolicyState = $($wpp.WindowsProtectedPrintGroupPolicyState)  (1 = ON: third-party drivers blocked)"

        "`n--- PrintService events, last 24h (errors/warnings) ---"
        foreach ($log in 'Microsoft-Windows-PrintService/Admin', 'Microsoft-Windows-PrintService/Operational') {
            try {
                Get-WinEvent -FilterHashtable @{ LogName = $log; Level = 1, 2, 3; StartTime = (Get-Date).AddDays(-1) } -MaxEvents 15 -ErrorAction Stop |
                    ForEach-Object { "[{0}] {1} id={2}: {3}" -f $_.TimeCreated, ($log -split '/')[-1], $_.Id, ($_.Message -replace '\s+', ' ').Substring(0, [math]::Min(300, $_.Message.Length)) }
            } catch { "  ($log): $($_.Exception.Message)" }
        }

        "`n--- Install logs ---"
        foreach ($log in "$outDir\Driver-Install.log", "$outDir\$PrinterName-Install.log") {
            if (Test-Path $log) { "## $log"; Get-Content $log -Tail 25 }
        }
    }
    $report | Tee-Object -FilePath $outFile
    Write-Host "`nSaved: $outFile" -ForegroundColor Cyan
}
