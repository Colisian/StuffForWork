# Save as: Deploy-IlliadODBC-Silent.ps1
# Deploys ILLiad ODBC configuration as User DSN (SILENT VERSION)
# For use with Intune/Company Portal automated deployment
#
# SECURITY WARNING: This script contains an embedded password in plain text
# AND stores the database password in the Windows registry at:
# HKCU:\SOFTWARE\ODBC\ODBC.INI\[DSN Name]\PWD
#
# Security Considerations:
# 1. This script file contains the password - protect file permissions
# 2. Password is read-only database access (limited scope)
# 3. Password is stored in user registry (ODBC limitation)
# 4. Any process running under the user account can read the password
# 5. Ensure workstations use full disk encryption and strong authentication
# 6. Consider using Windows Credential Manager or Azure Key Vault for production

# Enable transcript logging for troubleshooting Company Portal deployments
$transcriptPath = "$env:TEMP\IlliadODBC-Deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $transcriptPath -Force

try {
    $dsnName = "ILLiadLink"
    $serverName = "10.126.5.89"
    $database = "ILLData"
    $loginID = "ILLiadLink"

    # Embedded password for silent deployment
    # This is a READ-ONLY database account
    $plainPassword = "1qaz2wsx!QAZ@WSX"

    Write-Host "`n=== ILLiad ODBC Setup (Silent) ===" -ForegroundColor Cyan
    Write-Host "Transcript log: $transcriptPath" -ForegroundColor Gray
    Write-Host "Running as user: $env:USERNAME" -ForegroundColor Gray

    $psBitness = if ([Environment]::Is64BitProcess) { "64-bit" } else { "32-bit" }
    Write-Host "PowerShell bitness: $psBitness" -ForegroundColor Gray

    # Detect Office architecture with better error handling
    # Need to check both 64-bit and 32-bit registry paths when running from 64-bit PowerShell
    Write-Host "`nDetecting Office architecture..." -ForegroundColor Cyan

    $officeArch = $null
    $registryPaths = @(
        "HKLM:\Software\Microsoft\Office\ClickToRun\Configuration",
        "HKLM:\Software\Wow6432Node\Microsoft\Office\ClickToRun\Configuration"
    )

    foreach ($regPath in $registryPaths) {
        try {
            $config = Get-ItemProperty $regPath -ErrorAction Stop
            if ($config.Platform) {
                $officeArch = $config.Platform
                Write-Host "  Found Office in registry: $regPath" -ForegroundColor Gray
                Write-Host "  Office Platform value: $officeArch" -ForegroundColor Gray
                break
            }
        } catch {
            Write-Host "  Registry path not found: $regPath" -ForegroundColor Gray
        }
    }

    if (-not $officeArch) {
        Write-Host "  WARNING: Could not detect Office installation" -ForegroundColor Yellow
        Write-Host "  Defaulting to 32-bit Office assumption" -ForegroundColor Yellow
        $officeArch = "x86"
    }

    $platform = if ($officeArch -eq "x64") { "64-bit" } else { "32-bit" }
    Write-Host "Office Architecture: $platform" -ForegroundColor Green

    # Driver path selection - FIXED: was previously backwards
    # 32-bit Office needs 32-bit driver, 64-bit Office needs 64-bit driver
    # On 64-bit Windows: System32 = 64-bit DLLs, SysWOW64 = 32-bit DLLs
    $driverPath = if ($platform -eq "64-bit") {
        "C:\Windows\System32\sqlncli11.dll"  # 64-bit driver for 64-bit Office
    } else {
        "C:\Windows\SysWOW64\sqlncli11.dll"  # 32-bit driver for 32-bit Office
    }

    Write-Host "Expected driver path: $driverPath" -ForegroundColor Gray

    # Verify SQL Server Native Client driver exists
    if (-not (Test-Path $driverPath)) {
        Write-Host "`n✗ ERROR: SQL Server Native Client 11.0 driver not found" -ForegroundColor Red
        Write-Host "Expected location: $driverPath" -ForegroundColor Yellow
        Write-Host "Office Architecture: $platform" -ForegroundColor Yellow
        Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
        Write-Host "  1. Install SQL Server Native Client 11.0 matching your Office architecture" -ForegroundColor White
        Write-Host "  2. Download from: https://www.microsoft.com/en-us/download/details.aspx?id=50402" -ForegroundColor White
        Write-Host "  3. Choose sqlncli_x64.msi for 64-bit or sqlncli_x86.msi for 32-bit" -ForegroundColor White

        # List what drivers ARE installed for debugging
        Write-Host "`nSearching for installed SQL Native Client drivers:" -ForegroundColor Yellow
        $possiblePaths = @(
            "C:\Windows\System32\sqlncli11.dll",
            "C:\Windows\SysWOW64\sqlncli11.dll"
        )
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                Write-Host "  FOUND: $path" -ForegroundColor Green
            } else {
                Write-Host "  NOT FOUND: $path" -ForegroundColor Red
            }
        }

        throw "SQL Server Native Client 11.0 driver not found at expected location"
    }

    Write-Host "✓ Driver found: SQL Server Native Client 11.0" -ForegroundColor Green

    # Remove old DSN configurations
    Write-Host "`nRemoving existing DSN configuration (if any)..." -ForegroundColor Cyan
    try {
        Remove-OdbcDsn -Name $dsnName -DsnType User -Platform $platform -ErrorAction SilentlyContinue
        Write-Host "  Existing DSN removed (or didn't exist)" -ForegroundColor Gray
    } catch {
        Write-Host "  WARNING: Could not remove existing DSN: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Create registry paths for User DSN
    Write-Host "`nCreating registry entries for User DSN..." -ForegroundColor Cyan
    $regPath = "HKCU:\SOFTWARE\ODBC\ODBC.INI\$dsnName"
    $regListPath = "HKCU:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources"

    Write-Host "  Registry path: $regPath" -ForegroundColor Gray
    Write-Host "  Registry list path: $regListPath" -ForegroundColor Gray

    try {
        $null = New-Item -Path "HKCU:\SOFTWARE\ODBC\ODBC.INI" -Force -ErrorAction SilentlyContinue
        Write-Host "  Created/verified ODBC.INI base path" -ForegroundColor Gray

        $null = New-Item -Path $regListPath -Force -ErrorAction SilentlyContinue
        Write-Host "  Created/verified ODBC Data Sources path" -ForegroundColor Gray

        $null = New-Item -Path $regPath -Force -ErrorAction Stop
        Write-Host "  Created DSN registry key" -ForegroundColor Gray
    } catch {
        Write-Host "`n✗ ERROR: Failed to create registry entries" -ForegroundColor Red
        Write-Host "  Error message: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  This may indicate a permissions issue or registry corruption" -ForegroundColor Yellow
        throw "Failed to create registry entries for ODBC DSN"
    }

    # Configure ODBC DSN settings
    Write-Host "`nConfiguring ODBC DSN settings..." -ForegroundColor Cyan
    $settings = @{
        "Driver" = $driverPath
        "Server" = $serverName
        "Database" = $database
        "UID" = $loginID
        "PWD" = $plainPassword
        "Trusted_Connection" = "No"
        "Encrypt" = "No"
        "TrustServerCertificate" = "Yes"
        "ApplicationIntent" = "READONLY"
        "LoginTimeout" = "60"
        "QueryTimeout" = "0"
    }

    try {
        foreach ($key in $settings.Keys) {
            # Don't log password value
            if ($key -eq "PWD") {
                Write-Host "  Setting $key = [REDACTED]" -ForegroundColor Gray
            } else {
                Write-Host "  Setting $key = $($settings[$key])" -ForegroundColor Gray
            }
            Set-ItemProperty -Path $regPath -Name $key -Value $settings[$key] -Force -ErrorAction Stop
        }

        Write-Host "  Registering DSN in ODBC Data Sources list..." -ForegroundColor Gray
        Set-ItemProperty -Path $regListPath -Name $dsnName -Value "SQL Server Native Client 11.0" -Force -ErrorAction Stop

        Write-Host "✓ Registry configuration written successfully" -ForegroundColor Green
    } catch {
        Write-Host "`n✗ ERROR: Failed to configure ODBC settings" -ForegroundColor Red
        Write-Host "  Error message: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  Failed on key: $key" -ForegroundColor Yellow

        # Clean up password before exit
        $plainPassword = $null
        [System.GC]::Collect()

        throw "Failed to configure ODBC settings in registry"
    }

    # Clean up password from memory
    $plainPassword = $null
    [System.GC]::Collect()

    Write-Host "`n=== Configuration Complete ===" -ForegroundColor Cyan
    Write-Host "✓ User DSN '$dsnName' created successfully" -ForegroundColor Green
    Write-Host "`nTest in Microsoft Access:" -ForegroundColor Yellow
    Write-Host "  G:\Shared drives\Resource Sharing & Reserves\ILL" -ForegroundColor White
    Write-Host "`nNote: First connection may take 20-30 seconds." -ForegroundColor Gray
    Write-Host "`nSecurity Reminder: Password stored in user registry (HKCU)" -ForegroundColor Yellow
    Write-Host "Transcript saved to: $transcriptPath" -ForegroundColor Gray

    Stop-Transcript
    exit 0

} catch {
    # Top-level error handler
    Write-Host "`n`n✗✗✗ SCRIPT FAILED ✗✗✗" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "`nStack trace:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    Write-Host "`nTranscript log saved to: $transcriptPath" -ForegroundColor Yellow
    Write-Host "Please review the log file for detailed troubleshooting information." -ForegroundColor Yellow

    Stop-Transcript
    exit 1
}
