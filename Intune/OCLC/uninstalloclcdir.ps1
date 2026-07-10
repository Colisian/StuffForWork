<#
.SYNOPSIS
    Post-uninstall cleanup for OCLC Connexion: removes the public desktop
    shortcut and any leftover install directory.

.DESCRIPTION
    Runs after the MSI uninstalls (see uninstall.cmd). Stops Connexion if it is
    running (an open Connex.exe locks the install directory), then removes
    leftovers. A leftover directory that cannot be deleted is logged as a
    warning but does not fail the uninstall - the products themselves are
    already removed at this point.

.NOTES
    Author:  Colin McLeod
    Date:    2026-07-06
    Version: 2.0
#>

$oclcDir      = 'C:\Program Files\OCLC'
$shortcutPath = 'C:\Users\Public\Desktop\Connexion.lnk'

# Stop Connexion if running - it locks the install directory
Get-Process -Name 'Connex' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Remove the desktop shortcut created by oclcdeploy.ps1
if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    Write-Host "Removed shortcut: $shortcutPath"
}

# Remove leftover install directory
if (Test-Path -LiteralPath $oclcDir) {
    try {
        Remove-Item -LiteralPath $oclcDir -Recurse -Force -ErrorAction Stop
        Write-Host "Removed leftover directory: $oclcDir"
    } catch {
        Write-Warning "Could not remove '$oclcDir': $($_.Exception.Message). Leftover files remain."
    }
} else {
    Write-Host "No leftover directory at $oclcDir - nothing to clean up."
}

exit 0
