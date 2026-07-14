<#
.SYNOPSIS
    Intune Win32 custom detection script for the RemoveMicrosoft365 app.

.DESCRIPTION
    Detection semantics for Win32 apps:
      - STDOUT written AND exit 0  -> app is "installed" (i.e., device is clean)
      - exit 1 / no output         -> app "not installed" (Intune runs Install.ps1)

    Keys ONLY on the consumer SKUs. A later deployment of M365 Apps for
    enterprise (O365ProPlusRetail etc.) will NOT flip this back to
    "not installed", so the removal never re-fires against enterprise Office.

.NOTES
    Author  : Colin McLeod (cmcleod1@umd.edu)
    Date    : 2026-07-14
    Version : 1.0.0
    Upload this file in the Intune app's Detection rules blade
    (Rules format: "Use a custom detection script"). Do NOT package it
    inside the .intunewin.
#>
$consumerSkus = @('O365HomePremRetail', 'OneNoteFreeRetail')
$c2rConfig    = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'

try {
    $raw = (Get-ItemProperty -Path $c2rConfig -ErrorAction SilentlyContinue).ProductReleaseIds
    if ($raw) {
        $productIds = $raw -split ',' | ForEach-Object { $_.Trim() }
        $found = @($productIds | Where-Object { $_ -in $consumerSkus })
        if ($found) {
            # Consumer Office still present -> not detected -> Intune installs
            exit 1
        }
    }

    Write-Output 'Compliant: no consumer Office C2R SKUs present.'
    exit 0
}
catch {
    # Fail closed: treat errors as "not detected" so removal is attempted
    exit 1
}
