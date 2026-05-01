<#
.SYNOPSIS
    Intune detection script for LIBR-AdobeInstallerCleanup.ps1

.DESCRIPTION
    Checks for the flag file written by AdobeInstallerCleanup.ps1 at the end of
    a successful run. Two deployment variants are supported:

      Cleanup Only   → flag: C:\ProgramData\LIBR\Logs\AdobeInstallerCleanup-CleanOnly.flag
      With Uninstall → flag: C:\ProgramData\LIBR\Logs\AdobeInstallerCleanup-WithUninstall.flag

    Deploy this script as-is for the "Cleanup Only" app, or change $FlagSuffix
    to "WithUninstall" for the uninstall variant.

    Exit 0 = detected (script already ran successfully)
    Exit 1 = not detected (Intune should run the remediation)

.NOTES
    Author  : Oji (cmcleod1)
    Date    : 2026-04-20
    Version : 1.1
#>

# --- Change this value to match the Intune app variant ---
$FlagSuffix = "CleanOnly"   # or "WithUninstall"

$flagFile = "C:\ProgramData\LIBR\Logs\AdobeInstallerCleanup-$FlagSuffix.flag"

if (Test-Path -LiteralPath $flagFile) {
    Write-Output "Detected: $flagFile exists."
    exit 0
}

Write-Output "Not detected: $flagFile not found."
exit 1
