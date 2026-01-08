# Uninstall-IlliadODBC.ps1
# Removes ILLiad and Ares ODBC Setup desktop shortcuts and scripts
# For use with Intune Win32 App uninstallation
#
# Note: User ODBC DSN configurations (in HKCU) cannot be removed from SYSTEM context.
# Users will need to manually remove their DSN entries if needed, or the entries
# will be overwritten if they re-run the setup scripts.

# Enable transcript logging for troubleshooting
$transcriptPath = "$env:TEMP\IlliadODBC-Uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $transcriptPath -Force

try {
    Write-Host "`n=== Atlas ODBC Uninstall (ILLiad & Ares) ===" -ForegroundColor Cyan
    Write-Host "Transcript log: $transcriptPath" -ForegroundColor Gray
    Write-Host "Running as user: $env:USERNAME" -ForegroundColor Gray

    $illiadShortcut = "ILLiad ODBC Setup.lnk"
    $aresShortcut = "Ares ODBC Setup.lnk"
    $illiadScript = "C:\ProgramData\UMDLibraries\scripts\Deploy-IlliadODBC.ps1"
    $aresScript = "C:\ProgramData\UMDLibraries\scripts\Deploy-AresODBC.ps1"
    $illiadLauncher = "C:\ProgramData\UMDLibraries\scripts\Launch-IlliadODBC.vbs"
    $aresLauncher = "C:\ProgramData\UMDLibraries\scripts\Launch-AresODBC.vbs"
    $removedItems = @()

    # Get Public Desktop path (SYSTEM context)
    Write-Host "`nLocating Public Desktop path..." -ForegroundColor Cyan
    $desktopPath = Join-Path $env:PUBLIC "Desktop"
    Write-Host "  Desktop: $desktopPath" -ForegroundColor Gray

    # Remove ILLiad desktop shortcut
    $illiadShortcutPath = Join-Path $desktopPath $illiadShortcut
    Write-Host "`nRemoving ILLiad desktop shortcut..." -ForegroundColor Cyan
    Write-Host "  Path: $illiadShortcutPath" -ForegroundColor Gray

    if (Test-Path $illiadShortcutPath) {
        Remove-Item -Path $illiadShortcutPath -Force -ErrorAction Stop
        Write-Host "  ILLiad desktop shortcut removed" -ForegroundColor Green
        $removedItems += "ILLiad desktop shortcut"
    } else {
        Write-Host "  Shortcut not found (may already be removed)" -ForegroundColor Yellow
    }

    # Remove Ares desktop shortcut
    $aresShortcutPath = Join-Path $desktopPath $aresShortcut
    Write-Host "`nRemoving Ares desktop shortcut..." -ForegroundColor Cyan
    Write-Host "  Path: $aresShortcutPath" -ForegroundColor Gray

    if (Test-Path $aresShortcutPath) {
        Remove-Item -Path $aresShortcutPath -Force -ErrorAction Stop
        Write-Host "  Ares desktop shortcut removed" -ForegroundColor Green
        $removedItems += "Ares desktop shortcut"
    } else {
        Write-Host "  Shortcut not found (may already be removed)" -ForegroundColor Yellow
    }

    # Remove ILLiad PowerShell script
    Write-Host "`nRemoving ILLiad PowerShell script..." -ForegroundColor Cyan
    Write-Host "  Path: $illiadScript" -ForegroundColor Gray

    if (Test-Path $illiadScript) {
        Remove-Item -Path $illiadScript -Force -ErrorAction Stop
        Write-Host "  ILLiad PowerShell script removed" -ForegroundColor Green
        $removedItems += "ILLiad PowerShell script"
    } else {
        Write-Host "  Script not found (may already be removed)" -ForegroundColor Yellow
    }

    # Remove Ares PowerShell script
    Write-Host "`nRemoving Ares PowerShell script..." -ForegroundColor Cyan
    Write-Host "  Path: $aresScript" -ForegroundColor Gray

    if (Test-Path $aresScript) {
        Remove-Item -Path $aresScript -Force -ErrorAction Stop
        Write-Host "  Ares PowerShell script removed" -ForegroundColor Green
        $removedItems += "Ares PowerShell script"
    } else {
        Write-Host "  Script not found (may already be removed)" -ForegroundColor Yellow
    }

    # Remove ILLiad VBScript launcher
    Write-Host "`nRemoving ILLiad VBScript launcher..." -ForegroundColor Cyan
    Write-Host "  Path: $illiadLauncher" -ForegroundColor Gray

    if (Test-Path $illiadLauncher) {
        Remove-Item -Path $illiadLauncher -Force -ErrorAction Stop
        Write-Host "  ILLiad VBScript launcher removed" -ForegroundColor Green
        $removedItems += "ILLiad VBScript launcher"
    } else {
        Write-Host "  Launcher not found (may already be removed)" -ForegroundColor Yellow
    }

    # Remove Ares VBScript launcher
    Write-Host "`nRemoving Ares VBScript launcher..." -ForegroundColor Cyan
    Write-Host "  Path: $aresLauncher" -ForegroundColor Gray

    if (Test-Path $aresLauncher) {
        Remove-Item -Path $aresLauncher -Force -ErrorAction Stop
        Write-Host "  Ares VBScript launcher removed" -ForegroundColor Green
        $removedItems += "Ares VBScript launcher"
    } else {
        Write-Host "  Launcher not found (may already be removed)" -ForegroundColor Yellow
    }

    # Clean up scripts directory if empty
    $scriptsDir = "C:\ProgramData\UMDLibraries\scripts"
    if (Test-Path $scriptsDir) {
        $remainingFiles = Get-ChildItem -Path $scriptsDir -Force -ErrorAction SilentlyContinue
        if (-not $remainingFiles) {
            Remove-Item -Path $scriptsDir -Force -ErrorAction SilentlyContinue
            Write-Host "`nRemoved empty scripts directory" -ForegroundColor Gray
        }
    }

    # Note about user DSN configurations
    Write-Host "`n--- Note ---" -ForegroundColor Yellow
    Write-Host "User ODBC DSN configurations (ILLiadLink, AresLink) are stored in" -ForegroundColor Yellow
    Write-Host "each user's registry (HKCU) and cannot be removed from SYSTEM context." -ForegroundColor Yellow
    Write-Host "Users can remove these manually via ODBC Data Sources if needed." -ForegroundColor Yellow

    # Summary
    Write-Host "`n=== Uninstall Complete ===" -ForegroundColor Cyan
    if ($removedItems.Count -gt 0) {
        Write-Host "Removed items:" -ForegroundColor Green
        foreach ($item in $removedItems) {
            Write-Host "  $item" -ForegroundColor Green
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
