# Uninstall-IlliadODBC.ps1
# Removes ILLiad ODBC User DSN configuration
# For use with Intune/Company Portal uninstallation

$dsnName = "ILLiadLink"
$regPath = "HKCU:\SOFTWARE\ODBC\ODBC.INI\$dsnName"
$regListPath = "HKCU:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources"

Write-Host "`n=== ILLiad ODBC Uninstall ===" -ForegroundColor Cyan

# Detect Office architecture for proper ODBC cmdlet usage
$officeArch = (Get-ItemProperty "HKLM:\Software\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue).Platform
$platform = if ($officeArch -eq "x64") { "64-bit" } else { "32-bit" }

Write-Host "Detected platform: $platform" -ForegroundColor Gray

try {
    # Remove using PowerShell cmdlet
    Remove-OdbcDsn -Name $dsnName -DsnType User -Platform $platform -ErrorAction SilentlyContinue

    # Clean up registry entries
    if (Test-Path $regPath) {
        Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
        Write-Host "✓ Removed DSN registry key" -ForegroundColor Green
    }

    # Remove from DSN list
    if (Test-Path $regListPath) {
        $dsnList = Get-ItemProperty -Path $regListPath -ErrorAction SilentlyContinue
        if ($dsnList.$dsnName) {
            Remove-ItemProperty -Path $regListPath -Name $dsnName -Force -ErrorAction SilentlyContinue
            Write-Host "✓ Removed from ODBC Data Sources list" -ForegroundColor Green
        }
    }

    Write-Host "`n✓ ILLiad ODBC User DSN '$dsnName' removed successfully" -ForegroundColor Green
    exit 0

} catch {
    Write-Host "`n✗ ERROR: Failed to remove ODBC configuration" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    exit 1
}
