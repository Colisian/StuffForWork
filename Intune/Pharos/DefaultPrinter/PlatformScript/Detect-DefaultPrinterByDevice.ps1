<#
.SYNOPSIS
Detection script for the device-mapped default printer remediation.

.DESCRIPTION
Read-only counterpart to Set-DefaultPrinterByDevice.ps1. Pair the two as an
Intune Remediation (run in the logged-on user's context) when you want the
default printer re-checked on a schedule and reported on, rather than only
applied at sign-in.

Compliant means both of the following, because either alone is not durable:
  - the mapped queue is the current default, and
  - LegacyDefaultPrinterMode is 1, so Windows will not re-point the default at
    the most recently used queue.

A device whose name matches no rule is reported compliant: it is out of scope,
not broken.

Intune Remediation contract:
  exit 0 = compliant       (no remediation)
  exit 1 = non-compliant   (run the remediation script)
Keep STDOUT under 2048 characters.

Configure with:
  Run this script using the logged-on credentials : Yes
  Enforce script signature check                  : No
  Run script in 64-bit PowerShell                  : Yes

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-08-12
Version: 1.0.0

Keep the rule table below identical to Set-DefaultPrinterByDevice.ps1.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

# ---- Device name to default printer map (keep in sync with the remediation) ----
$deviceRule = @(
    [pscustomobject]@{ Pattern = 'LIBRWKMCKP2WF*'; PrinterName = 'LIB-Mck2FWideFormat'; Location = 'McKeldin 2nd Floor Wide Format' }
    [pscustomobject]@{ Pattern = 'LIBRWKMCK*'; PrinterName = 'LIB-MckBW'; Location = 'McKeldin Library' }
    [pscustomobject]@{ Pattern = 'LIBRWKSTEM*'; PrinterName = 'LIB-EPSLBW'; Location = 'STEM Library (EPSL)' }
    [pscustomobject]@{ Pattern = 'LIBRWKART*'; PrinterName = 'LIB-ArtBW'; Location = 'Art Library' }
    [pscustomobject]@{ Pattern = 'LIBRWKMDRP*'; PrinterName = 'LIB-MarylandRoomBW'; Location = 'Maryland Room' }
    [pscustomobject]@{ Pattern = 'LIBRWKPAL*'; PrinterName = 'LIB-PALBW'; Location = 'Performing Arts Library' }
    [pscustomobject]@{ Pattern = 'LIBRWKARCH*'; PrinterName = 'LIB-ArchBW'; Location = 'Architecture Library' }
)

try {
    # Most-specific match wins, so LIBRWKMCKP2WF beats the broader LIBRWKMCK
    # regardless of the order rules appear above.
    $match = @($deviceRule | Where-Object { $env:COMPUTERNAME -like $_.Pattern })
    if ($match.Count -eq 0) {
        Write-Output "No rule matches $env:COMPUTERNAME; out of scope."
        exit 0
    }

    $rule = $match | Sort-Object -Property @{ Expression = { $_.Pattern.TrimEnd('*').Length } } -Descending |
        Select-Object -First 1

    $printer = Get-CimInstance -ClassName Win32_Printer -Filter "Name='$($rule.PrinterName)'" -ErrorAction SilentlyContinue
    if (-not $printer) {
        Write-Output "Queue '$($rule.PrinterName)' is not installed."
        exit 1
    }

    if (-not $printer.Default) {
        $currentDefault = Get-CimInstance -ClassName Win32_Printer -Filter 'Default=True' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        Write-Output "Default is '$(if ($currentDefault) { $currentDefault.Name } else { 'none' })', expected '$($rule.PrinterName)'."
        exit 1
    }

    $legacyMode = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' `
            -Name 'LegacyDefaultPrinterMode' -ErrorAction SilentlyContinue).LegacyDefaultPrinterMode
    if ($legacyMode -ne 1) {
        Write-Output "'$($rule.PrinterName)' is default but Windows still manages the default printer."
        exit 1
    }

    Write-Output "Compliant: '$($rule.PrinterName)' ($($rule.Location))."
    exit 0
}
catch {
    # Report non-compliant on an unexpected error so the remediation gets a turn.
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
