#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Intune detection rule for JWrapper Remote Access / SimpleHelp.

.DESCRIPTION
    Used as the "Detection Rules > Custom detection script" in an Intune
    Win32 app. Exit 0 = software IS present (needs remediation).
    Exit 1 = software NOT present (compliant).

    Intune interprets:
      Exit 0  → Detected (will trigger install/remediation)
      Non-0   → Not detected (skip)
#>

$DetectionPaths = @(
    "C:\ProgramData\JWrapper-Remote Access",
    "C:\ProgramData\SimpleHelp",
    "C:\Program Files\JWrapper-Remote Access",
    "C:\Program Files (x86)\JWrapper-Remote Access",
    "C:\Program Files\SimpleHelp",
    "C:\Program Files (x86)\SimpleHelp"
)

$DetectedService = Get-Service -Name "JWrapper*" -ErrorAction SilentlyContinue
$DetectedPath    = $DetectionPaths | Where-Object { Test-Path $_ }

if ($DetectedService -or $DetectedPath) {
    # Software found — signal Intune to run remediation
    Write-Output "DETECTED: JWrapper/SimpleHelp artifacts found."
    exit 0
} else {
    # Clean
    exit 1
}