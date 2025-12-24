# Detect-IlliadODBC.ps1
# Detection script for Intune Win32 App deployment (SYSTEM context)
# Checks if ILLiad ODBC Setup desktop shortcut exists on Public Desktop
#
# Exit 0 with output = Detected (installed)
# Exit 1 or no output = Not detected (not installed)

$shortcutName = "ILLiad ODBC Setup.lnk"

try {
    # Use Public Desktop for all users (SYSTEM context)
    $desktopPath = Join-Path $env:PUBLIC "Desktop"

    # Full path to shortcut
    $shortcutPath = Join-Path $desktopPath $shortcutName

    # Check if shortcut exists
    if (Test-Path $shortcutPath) {
        Write-Output "ILLiad ODBC Setup shortcut found at: $shortcutPath"
        exit 0
    }

    # Shortcut not found
    Write-Output "ILLiad ODBC Setup shortcut not found at: $shortcutPath"
    exit 1

} catch {
    # Any error means not properly configured
    Write-Output "Error detecting shortcut: $($_.Exception.Message)"
    exit 1
}
