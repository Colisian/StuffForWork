# Uninstall-IlliadODBC.ps1
# Removes ILLiad ODBC Setup desktop shortcut and optionally cleans up ODBC DSN
# For use with Intune Win32 App uninstallation

# Enable transcript logging for troubleshooting
$transcriptPath = "$env:TEMP\IlliadODBC-Uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $transcriptPath -Force

try {
    Write-Host "`n=== ILLiad ODBC Uninstall ===" -ForegroundColor Cyan
    Write-Host "Transcript log: $transcriptPath" -ForegroundColor Gray
    Write-Host "Running as user: $env:USERNAME" -ForegroundColor Gray

    $shortcutName = "ILLiad ODBC Setup.lnk"
    $dsnName = "ILLiadLink"
    $removedItems = @()

    # Get user's desktop path
    Write-Host "`nLocating desktop path..." -ForegroundColor Cyan
    $desktopPath = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction Stop).Desktop
    $desktopPath = [System.Environment]::ExpandEnvironmentVariables($desktopPath)
    Write-Host "  Desktop: $desktopPath" -ForegroundColor Gray

    # Remove desktop shortcut
    $shortcutPath = Join-Path $desktopPath $shortcutName
    Write-Host "`nRemoving desktop shortcut..." -ForegroundColor Cyan
    Write-Host "  Path: $shortcutPath" -ForegroundColor Gray

    if (Test-Path $shortcutPath) {
        Remove-Item -Path $shortcutPath -Force -ErrorAction Stop
        Write-Host "  ✓ Desktop shortcut removed" -ForegroundColor Green
        $removedItems += "Desktop shortcut"
    } else {
        Write-Host "  Shortcut not found (may already be removed)" -ForegroundColor Yellow
    }

    # Clean up ODBC DSN if it exists
    Write-Host "`nChecking for ODBC DSN configuration..." -ForegroundColor Cyan
    $regPath = "HKCU:\SOFTWARE\ODBC\ODBC.INI\$dsnName"
    $regListPath = "HKCU:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources"

    if (Test-Path $regPath) {
        Write-Host "  Found ODBC DSN configuration, removing..." -ForegroundColor Gray

        # Detect Office architecture for proper ODBC cmdlet usage
        $officeArch = (Get-ItemProperty "HKLM:\Software\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue).Platform
        $platform = if ($officeArch -eq "x64") { "64-bit" } else { "32-bit" }
        Write-Host "  Detected platform: $platform" -ForegroundColor Gray

        # Remove using PowerShell cmdlet
        Remove-OdbcDsn -Name $dsnName -DsnType User -Platform $platform -ErrorAction SilentlyContinue

        # Clean up registry entries
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
            Write-Host "  ✓ Removed DSN registry key" -ForegroundColor Green
            $removedItems += "ODBC DSN registry configuration"
        }

        # Remove from DSN list
        if (Test-Path $regListPath) {
            $dsnList = Get-ItemProperty -Path $regListPath -ErrorAction SilentlyContinue
            if ($dsnList.$dsnName) {
                Remove-ItemProperty -Path $regListPath -Name $dsnName -Force -ErrorAction SilentlyContinue
                Write-Host "  ✓ Removed from ODBC Data Sources list" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "  No ODBC DSN configuration found" -ForegroundColor Gray
    }

    # Summary
    Write-Host "`n=== Uninstall Complete ===" -ForegroundColor Cyan
    if ($removedItems.Count -gt 0) {
        Write-Host "Removed items:" -ForegroundColor Green
        foreach ($item in $removedItems) {
            Write-Host "  ✓ $item" -ForegroundColor Green
        }
    } else {
        Write-Host "No items found to remove (may already be uninstalled)" -ForegroundColor Yellow
    }

    Write-Host "`nTranscript saved to: $transcriptPath" -ForegroundColor Gray
    Stop-Transcript
    exit 0

} catch {
    Write-Host "`n✗ ERROR: Uninstall failed" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host "`nTranscript saved to: $transcriptPath" -ForegroundColor Yellow
    Stop-Transcript
    exit 1
}
