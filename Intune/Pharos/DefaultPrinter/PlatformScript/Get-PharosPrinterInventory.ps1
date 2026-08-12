<#
.SYNOPSIS
Reports the real spooler queue names on a machine so the default printer
mapping can be confirmed against reality.

.DESCRIPTION
Run this on an actual lab PC. It answers one question: what string does
Set-DefaultPrinterByDevice.ps1 need to match?

That string is the **spooler queue name** (Win32_Printer.Name), which is not
always what Settings > Printers & scanners displays:

  - Locally installed queue (what the Pharos EXEs create)
        Name = 'McKeldinBW'                   Settings shows: McKeldinBW
  - Connection to a shared print server queue
        Name = '\\LIBRPS403v\MCK_1F_PR4'      Settings shows: MCK_1F_PR4
  - Redirected over RDP / Windows 365
        Name = 'McKeldin ... (redirected 1)'  belongs to the CLIENT, not this PC

The Source column below flags which kind each printer is, so a machine whose
printers arrive from the print server rather than the Pharos Popup installer is
immediately obvious.

.PARAMETER Filter
Wildcard limiting which queues are listed. Defaults to everything.

.EXAMPLE
.\Get-PharosPrinterInventory.ps1

.EXAMPLE
.\Get-PharosPrinterInventory.ps1 -Filter '*Mck*'

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-08-12
Version: 1.0.0

Read-only. Safe to run as a standard user; no changes are made.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Filter = '*'
)

$ErrorActionPreference = 'Stop'

function Get-PrinterSource {
    <#
    .SYNOPSIS
    Classifies how a print queue reached this machine.

    .PARAMETER Printer
    A Win32_Printer instance.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Printer
    )

    if ($Printer.Name -match '\(redirected \d+\)$') {
        return 'RDP-redirected (client PC)'
    }

    if ($Printer.Name -like '\\\\*') {
        return 'Print server connection'
    }

    if ($Printer.PortName -like 'Pharos*' -or $Printer.PortName -like 'PS[0-9]*') {
        return 'Pharos Popup (local)'
    }

    if ($Printer.Network) {
        return 'Network'
    }

    return 'Local'
}

try {
    Write-Host ''
    Write-Host "Device name : $env:COMPUTERNAME"
    Write-Host "User        : $env:USERNAME"
    Write-Host ''

    $printers = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop |
            Where-Object { $_.Name -like $Filter })

    if ($printers.Count -eq 0) {
        Write-Host "No printers matched '$Filter'."
        exit 0
    }

    $printers |
        Select-Object @{ Name = 'QueueName(match this)'; Expression = { $_.Name } },
        @{ Name = 'Source'; Expression = { Get-PrinterSource -Printer $_ } },
        PortName,
        @{ Name = 'Default'; Expression = { $_.Default } },
        DriverName |
        Sort-Object 'QueueName(match this)' |
        Format-Table -AutoSize -Wrap

    Write-Host ''
    Write-Host '--- Pharos Popup queues installed locally (these are the names to map) ---'
    # Identified by the Pharos port, not by a name prefix: the queues carry no
    # 'LIB-' prefix even though the vendor installers and their manifests do.
    $pharos = @($printers | Where-Object {
            $_.Name -notmatch '\(redirected \d+\)$' -and
            ($_.PortName -like 'Pharos*' -or $_.PortName -like 'PS[0-9]*')
        })

    if ($pharos.Count -eq 0) {
        Write-Host '  NONE FOUND. Either the Pharos package is not installed on this PC,'
        Write-Host '  or this fleet gets its queues by another route. Use the exact strings'
        Write-Host '  in the QueueName column above in the script mapping.'
    }
    else {
        $pharos | ForEach-Object { Write-Host "  $($_.Name)   [port $($_.PortName)]" }
    }

    Write-Host ''
    Write-Host '--- Current default ---'
    $default = $printers | Where-Object { $_.Default } | Select-Object -First 1
    Write-Host "  Win32_Printer default : $(if ($default) { $default.Name } else { '<none>' })"

    $windowsKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'
    $device = (Get-ItemProperty -LiteralPath $windowsKey -Name 'Device' -ErrorAction SilentlyContinue).Device
    $legacyMode = (Get-ItemProperty -LiteralPath $windowsKey -Name 'LegacyDefaultPrinterMode' -ErrorAction SilentlyContinue).LegacyDefaultPrinterMode

    Write-Host "  HKCU Device value     : $(if ($device) { $device } else { '<not set>' })"
    Write-Host "  LegacyDefaultPrinterMode : $(if ($null -eq $legacyMode) { '<not set>' } else { $legacyMode })"

    if ($legacyMode -ne 1) {
        Write-Host ''
        Write-Host '  NOTE: Windows is managing the default printer on this PC, so the'
        Write-Host '        default will drift to the last-used queue. The deployment'
        Write-Host '        script sets LegacyDefaultPrinterMode = 1 to stop that.'
    }

    Write-Host ''
    exit 0
}
catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
