<#
.SYNOPSIS
    Intune custom detection for the Epson TM-T20II APD5 copy-installation package.

.DESCRIPTION
    Installed = all of:
      - Sentinel HKLM:\SOFTWARE\UMDLibraries\Intune\EpsonTMT20II-APD\Version >= 5.13.0.0
      - Printer driver 'EPSON TM-T20II Receipt5' registered
      - EPSON Port Handler Monitor registered
      - A queue using that driver exists on an ESDPRT### port (created by the copy
        installation whether or not the printer is plugged in)

    Intune rule: exit 0 WITH stdout = detected; anything else = not detected.
    Set "Run script as 32-bit process on 64-bit clients" = No.

.NOTES
    Author:  Oji
    Date:    2026-09-28
    Version: 4.0.0
#>
$ErrorActionPreference = 'SilentlyContinue'

$requiredVersion = [version]'5.13.0.0'
$sentinelKey     = 'HKLM:\SOFTWARE\UMDLibraries\Intune\EpsonTMT20II-APD'
$driverName      = 'EPSON TM-T20II Receipt5'
$monitorKey      = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\EPSON Port Handler Monitor'

$installedVersion = $null
$raw = (Get-ItemProperty -Path $sentinelKey -Name 'Version').Version
if ($raw) { [void][version]::TryParse($raw, [ref]$installedVersion) }

$hasSentinel = $installedVersion -and ($installedVersion -ge $requiredVersion)
$hasDriver   = [bool](Get-PrinterDriver -Name $driverName)
$hasMonitor  = Test-Path $monitorKey
$queue       = Get-Printer | Where-Object { $_.DriverName -eq $driverName -and $_.PortName -like 'ESDPRT*' } | Select-Object -First 1

if ($hasSentinel -and $hasDriver -and $hasMonitor -and $queue) {
    Write-Output "Epson TM-T20II APD $installedVersion detected: '$($queue.Name)' on $($queue.PortName)"
    exit 0
}
exit 1
