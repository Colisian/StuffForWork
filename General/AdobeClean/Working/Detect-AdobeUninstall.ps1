<#
.SYNOPSIS
    Intune detection script for Uninstall-AdobeProducts.ps1

.DESCRIPTION
    Detected (exit 0) only when BOTH are true:
      1. The sentinel HKLM\SOFTWARE\LIBR\AdobeUninstall\Completed = 1
         (proves the script ran to the end and found nothing left to remove)
      2. A live re-check of the Uninstall hives finds no Adobe product other
         than the kept ones (Creative Cloud desktop app, Adobe Genuine Service)
         - so a later reinstall of e.g. Acrobat flips the device back to
         "not detected" and Intune re-runs the removal.

    If the removal ran with -RemoveCreativeCloud it stamps FullRemoval = 1 on
    the sentinel, and this script drops the keep list entirely: Creative Cloud
    reappearing then correctly reads as "not detected".

    Otherwise keep $KeepPattern in sync with the -KeepPattern used when
    deploying.

    Exit 0 = detected / compliant
    Exit 1 = not detected -> Intune runs the install (uninstall) script

.NOTES
    Author  : Oji (cmcleod1)
    Date    : 2026-09-01
    Version : 1.2.0

    CHANGELOG
      1.2.0 - Honours the FullRemoval sentinel written by -RemoveCreativeCloud
              (keep list is dropped, so a returning CC app is not detected).
      1.1.0 - Live re-check of the Uninstall hives; package wrappers ignored.
#>

$KeepPattern = @('Adobe Creative Cloud', 'Adobe Genuine Service')
$SentinelKey = 'HKLM:\SOFTWARE\LIBR\AdobeUninstall'

$sentinel = Get-ItemProperty -Path $SentinelKey -ErrorAction SilentlyContinue
if ($sentinel.Completed -ne 1) {
    Write-Output "Not detected: sentinel Completed=$($sentinel.Completed)"
    exit 1
}

# Deployed as a full wipe: nothing Adobe is allowed to remain, Creative Cloud included.
if ($sentinel.FullRemoval -eq 1) { $KeepPattern = @() }

$hives = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$remaining = @(Get-ItemProperty $hives -ErrorAction SilentlyContinue | Where-Object {
    if (-not $_.DisplayName) { return $false }
    if (-not ($_.Publisher -match '^Adobe' -or $_.DisplayName -match '^Adobe\b')) { return $false }
    if ([string]$_.DisplayVersion -eq '1.0.0000') { return $false }   # Admin Console package wrapper MSI, not a product
    $name = $_.DisplayName
    foreach ($p in $KeepPattern) { if ($name -match $p) { return $false } }
    return $true
})

if ($remaining.Count -gt 0) {
    Write-Output "Not detected: $($remaining.Count) Adobe product(s) still installed: $(($remaining.DisplayName | Select-Object -First 5) -join '; ')"
    exit 1
}

Write-Output 'Detected: no Adobe products remain other than kept ones.'
exit 0
