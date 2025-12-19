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

$dsnName = "ILLiadLink"
$serverName = "10.126.5.89"
$database = "ILLData"
$loginID = "ILLiadLink"

# Embedded password for silent deployment
# This is a READ-ONLY database account
$plainPassword = "1qaz2wsx!QAZ@WSX"

Write-Host "`n=== ILLiad ODBC Setup (Silent) ===" -ForegroundColor Cyan

# Detect Office
$officeArch = (Get-ItemProperty "HKLM:\Software\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue).Platform
$platform = if ($officeArch -eq "x64") { "64-bit" } else { "32-bit" }
$driverPath = if ($platform -eq "64-bit") { "C:\Windows\System32\sqlncli11.dll" } else { "C:\Windows\SysWOW64\sqlncli11.dll" }

Write-Host "Office: $platform" -ForegroundColor Green

# Verify SQL Server Native Client driver exists
if (-not (Test-Path $driverPath)) {
    Write-Host "`n✗ ERROR: SQL Server Native Client 11.0 driver not found" -ForegroundColor Red
    Write-Host "Expected location: $driverPath" -ForegroundColor Yellow
    Write-Host "`nInstall SQL Server Native Client 11.0:" -ForegroundColor Yellow
    Write-Host "  Download from: https://www.microsoft.com/en-us/download/details.aspx?id=50402" -ForegroundColor White
    exit 1
}

Write-Host "✓ Driver found: SQL Server Native Client 11.0" -ForegroundColor Green

# Remove old DSN configurations
Remove-OdbcDsn -Name $dsnName -DsnType User -Platform $platform -ErrorAction SilentlyContinue

# Create registry paths for User DSN
$regPath = "HKCU:\SOFTWARE\ODBC\ODBC.INI\$dsnName"
$regListPath = "HKCU:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources"

try {
    $null = New-Item -Path "HKCU:\SOFTWARE\ODBC\ODBC.INI" -Force -ErrorAction SilentlyContinue
    $null = New-Item -Path $regListPath -Force -ErrorAction SilentlyContinue
    $null = New-Item -Path $regPath -Force -ErrorAction Stop
} catch {
    Write-Host "`n✗ ERROR: Failed to create registry entries" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    exit 1
}

# Configure ODBC DSN settings
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
        Set-ItemProperty -Path $regPath -Name $key -Value $settings[$key] -Force -ErrorAction Stop
    }

    Set-ItemProperty -Path $regListPath -Name $dsnName -Value "SQL Server Native Client 11.0" -Force -ErrorAction Stop

    Write-Host "✓ Registry configuration written successfully" -ForegroundColor Green
} catch {
    Write-Host "`n✗ ERROR: Failed to configure ODBC settings" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow

    # Clean up password before exit
    $plainPassword = $null
    [System.GC]::Collect()

    exit 1
}

$plainPassword = $null
[System.GC]::Collect()

Write-Host "`n=== Configuration Complete ===" -ForegroundColor Cyan
Write-Host "✓ User DSN '$dsnName' created successfully" -ForegroundColor Green
Write-Host "`nTest in Microsoft Access:" -ForegroundColor Yellow
Write-Host "  G:\Shared drives\Resource Sharing & Reserves\ILL" -ForegroundColor White
Write-Host "`nNote: First connection may take 20-30 seconds." -ForegroundColor Gray
Write-Host "`nSecurity Reminder: Password stored in user registry (HKCU)" -ForegroundColor Yellow

exit 0
