# Detect-IlliadODBC.ps1
# Detection script for Intune Win32 App deployment (SYSTEM context)
# Checks if both ILLiad and Ares ODBC Setup desktop shortcuts exist on Public Desktop
#
# Exit 0 with output = Detected (installed)
# Exit 1 or no output = Not detected (not installed)

$illiadShortcut = "ILLiad ODBC Setup.lnk"
$aresShortcut = "Ares ODBC Setup.lnk"

try {
    # Use Public Desktop for all users (SYSTEM context)
    $desktopPath = Join-Path $env:PUBLIC "Desktop"

    # Full paths to shortcuts
    $illiadPath = Join-Path $desktopPath $illiadShortcut
    $aresPath = Join-Path $desktopPath $aresShortcut

    # Check if both shortcuts exist
    $illiadExists = Test-Path $illiadPath
    $aresExists = Test-Path $aresPath

    if ($illiadExists -and $aresExists) {
        Write-Output "Both ODBC Setup shortcuts found"
        Write-Output "  ILLiad: $illiadPath"
        Write-Output "  Ares: $aresPath"
        exit 0
    }

    # Report what's missing
    if (-not $illiadExists) {
        Write-Output "ILLiad ODBC Setup shortcut not found at: $illiadPath"
    }
    if (-not $aresExists) {
        Write-Output "Ares ODBC Setup shortcut not found at: $aresPath"
    }
    exit 1

} catch {
    # Any error means not properly configured
    Write-Output "Error detecting shortcuts: $($_.Exception.Message)"
    exit 1
}
