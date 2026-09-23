<#
.SYNOPSIS
    Gathers the facts needed to finalize the direct-IP printer packages. Read-only.

.DESCRIPTION
    For every printer in the master CSV:
      - Reads the matching queue on the print server (driver name, port, port host address,
        location) - this is the ground truth for which driver the queue uses today.
      - Resolves the PortAddress from the master CSV (and the print server's port host, if different).
      - Tests TCP 9100 to the DDNS name from this machine.
    Also lists every driver installed on the print server, so you can see the exact
    DriverName strings (these must match the INF exactly).

    Run from a domain-joined admin workstation on the staff network/VPN.

.PARAMETER PrintServer
    Default: LIBRPS403v.ad.umd.edu

.EXAMPLE
    .\Get-StaffPrinterInventory.ps1 | Tee-Object -Variable inv | Format-Table
    $inv | Export-Csv .\inventory-results.csv -NoTypeInformation

.NOTES
    Author:  Oji (cmcleod1@umd.edu)
    Date:    2026-09-22
    Version: 1.0.0
#>
[CmdletBinding()]
param(
    [string]$PrintServer = 'LIBRPS403v.ad.umd.edu',
    [string]$MasterCsv,
    [string]$DnsSuffix = 'resource.dyn.umd.edu',
    [switch]$SkipPortTest
)

begin {
    $ErrorActionPreference = 'Stop'
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    if (-not $MasterCsv) { $MasterCsv = Join-Path $ScriptDir 'StaffPrinters-DirectIP.csv' }

    function Resolve-HostSafe {
        [CmdletBinding()]
        param([string]$HostName)
        if (-not $HostName) { return $null }
        try {
            ((Resolve-DnsName -Name $HostName -Type A -DnsOnly -ErrorAction Stop |
                Where-Object IPAddress).IPAddress) -join ';'
        } catch { 'NXDOMAIN/ERR' }
    }
}

process {
    $serverQueues = @{}
    $serverPorts  = @{}
    try {
        Get-Printer -ComputerName $PrintServer | ForEach-Object { $serverQueues[$_.Name] = $_ }
        Get-PrinterPort -ComputerName $PrintServer | ForEach-Object { $serverPorts[$_.Name] = $_ }

        Write-Host "`n=== Drivers installed on $PrintServer ===" -ForegroundColor Cyan
        Get-PrinterDriver -ComputerName $PrintServer |
            Sort-Object Name | Format-Table Name, MajorVersion, Manufacturer, InfPath -AutoSize | Out-Host
    } catch {
        Write-Warning "Could not query $PrintServer ($($_.Exception.Message)). Continuing with DNS checks only."
    }

    foreach ($row in Import-Csv -Path $MasterCsv) {
        $name  = $row.Name.Trim()
        $fqdn  = if ($row.PortAddress) { $row.PortAddress.Trim() } else { "$name.$DnsSuffix" }
        $queue = $serverQueues[$name]
        $port  = if ($queue) { $serverPorts[$queue.PortName] }

        $ddnsIp = Resolve-HostSafe -HostName $fqdn
        $open = $null
        if (-not $SkipPortTest -and $ddnsIp -ne 'NXDOMAIN/ERR') {
            $open = (Test-NetConnection -ComputerName $fqdn -Port 9100 -WarningAction SilentlyContinue).TcpTestSucceeded
        }

        [pscustomobject]@{
            Name              = $name
            OnServer          = [bool]$queue
            ServerDriver      = $queue.DriverName
            ServerPort        = $queue.PortName
            ServerPortHost    = $port.PrinterHostAddress
            ServerPortHostIP  = Resolve-HostSafe -HostName $port.PrinterHostAddress
            ServerLocation    = $queue.Location
            DdnsName          = $fqdn
            DdnsIP            = $ddnsIp
            Port9100Open      = $open
        }
    }
}
