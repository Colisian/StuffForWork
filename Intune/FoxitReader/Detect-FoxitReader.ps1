<#
.SYNOPSIS
    Intune Win32 custom detection script for Foxit PDF Reader.

.DESCRIPTION
    Reports the app as installed when a Foxit PDF Reader registration exists with a
    DisplayVersion at or above $MinimumVersion.

    Detection is anchored on the ARP registration rather than on a file, because the Foxit
    bootstrapper installs Setup.msi (2025.2.0.33046) and then applies Setup.msp to reach
    2026.1.2.36540. A file-version rule against the base MSI version would false-positive on
    a half-patched install; the ARP DisplayVersion reflects the patched state.

    $MinimumVersion is deliberately set to 2026.1.0.0 - above the unpatched base MSI version
    and at or below the fully patched product version - so a bootstrapper run that installed
    the MSI but failed to apply the MSP is correctly reported as NOT detected.

    Intune contract for detection scripts:
        detected     = exit code 0 AND at least one line on STDOUT
        not detected = exit code 0 AND empty STDOUT
    Note this differs from the Remediations contract (0 = compliant, 1 = remediate).

    Configure the app with "Run script as 32-bit process on 64-bit clients" = No.

.NOTES
    Author  : Oji McLeod (cmcleod1@umd.edu) - ITFO / Digital Services & Technologies, UMD Libraries
    Date    : 2026-08-12
    Version : 1.0.0
    Stdout  : kept well under the 2048 character Intune limit
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

$minimumVersion = [version]'2026.1.0.0'

$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

$match = $null

foreach ($root in $uninstallRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }

    foreach ($key in (Get-ChildItem -LiteralPath $root)) {
        $props = Get-ItemProperty -LiteralPath $key.PSPath
        if ($props.DisplayName -notlike 'Foxit PDF Reader*') { continue }
        if ($props.SystemComponent -eq 1) { continue }

        $parsed = $null
        if (-not [version]::TryParse(($props.DisplayVersion -as [string]), [ref]$parsed)) { continue }
        if ($parsed -lt $minimumVersion) { continue }

        if (-not $match -or $parsed -gt $match.Version) {
            $match = [pscustomobject]@{
                Name    = $props.DisplayName
                Version = $parsed
            }
        }
    }
}

if ($match) {
    Write-Output "Detected: $($match.Name) $($match.Version)"
    exit 0
}

# No output + exit 0 => Intune treats the app as not installed.
exit 0
