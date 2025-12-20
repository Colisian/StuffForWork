# Detect-IlliadODBC.ps1
# Detection script for Intune Win32 App deployment
# Checks if ILLiad ODBC Setup desktop shortcut exists
#
# Exit 0 with output = Detected (installed)
# Exit 1 or no output = Not detected (not installed)

$shortcutName = "ILLiad ODBC Setup.lnk"

try {
    # Get user's desktop path from registry
    $desktopPath = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction Stop).Desktop

    # Expand environment variables
    $desktopPath = [System.Environment]::ExpandEnvironmentVariables($desktopPath)

    # Full path to shortcut
    $shortcutPath = Join-Path $desktopPath $shortcutName

    # Check if shortcut exists
    if (Test-Path $shortcutPath) {
        Write-Output "ILLiad ODBC Setup shortcut found at: $shortcutPath"
        exit 0
    }

    # Shortcut not found
    Write-Output "ILLiad ODBC Setup shortcut not found"
    exit 1

} catch {
    # Any error means not properly configured
    Write-Output "Error detecting shortcut: $($_.Exception.Message)"
    exit 1
}
