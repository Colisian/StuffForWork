<#
.SYNOPSIS
    Intune Uninstallation Script for Toggle Secure Print utility
    
.DESCRIPTION
    Removes the Toggle Secure Print utility and desktop shortcut.
    Handles both User context and System context installations.
    
.NOTES
    Deploy as: Same context as installation (User or System)
    Uninstall command: powershell.exe -ExecutionPolicy Bypass -File Uninstall-ToggleSecurePrint.ps1
#>

$ErrorActionPreference = "SilentlyContinue"

# Check both possible installation locations
$installDirs = @(
    "$env:ProgramData\UMDLibraries\SecurePrintToggle",
    "$env:LOCALAPPDATA\UMDLibraries\SecurePrintToggle"
)

$desktopPaths = @(
    "$env:PUBLIC\Desktop",
    [Environment]::GetFolderPath("Desktop")
)

# Remove desktop shortcuts
foreach ($desktop in $desktopPaths) {
    $shortcutPath = Join-Path $desktop "Toggle Secure Print.lnk"
    if (Test-Path $shortcutPath) {
        Remove-Item -Path $shortcutPath -Force
        Write-Host "Removed shortcut: $shortcutPath"
    }
}

# Remove installation directories
foreach ($installDir in $installDirs) {
    if (Test-Path $installDir) {
        Remove-Item -Path $installDir -Recurse -Force
        Write-Host "Removed directory: $installDir"
        
        # Clean up parent directory if empty
        $parentDir = Split-Path $installDir -Parent
        if ((Test-Path $parentDir) -and ((Get-ChildItem $parentDir -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0)) {
            Remove-Item -Path $parentDir -Force
        }
    }
}

Write-Host "Toggle Secure Print uninstalled successfully"
exit 0