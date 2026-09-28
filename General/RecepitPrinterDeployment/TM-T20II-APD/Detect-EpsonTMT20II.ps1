<#
.SYNOPSIS
    Intune custom detection for the Epson TM-T20II APD5 package.

.DESCRIPTION
    Detects the INSTALL STATE, not the physical printer. The v2 detection looked for the
    printer queue, which only exists while the TM-T20II is plugged in, so Company Portal
    reported "failed" on any machine where the printer was unplugged at install time.

    Installed = all of:
      - Sentinel HKLM:\SOFTWARE\UMDLibraries\Intune\EpsonTMT20II-APD\Version >= 5.13.0.0
      - Printer driver 'EPSON TM-T20II Receipt5' registered
      - EPSON Port Handler Monitor (ESDPRT ports) registered

    Intune rule: exit 0 WITH stdout = detected; anything else = not detected.
    Set "Run script as 32-bit process on 64-bit clients" = No.

.NOTES
    Author:  Oji
    Date:    2026-09-28
    Version: 3.0.0
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

if ($hasSentinel -and $hasDriver -and $hasMonitor) {
    Write-Output "Epson TM-T20II APD $installedVersion detected"
    exit 0
}
exit 1
