# Save as: Deploy-ILLiadODBC-NoTest.ps1
# Deploys configuration without connection test

#Requires -RunAsAdministrator

$dsnName = "ILLiadLink"
$serverName = "LIBRAP013V.AD.UMD.EDU"
$database = "ILLData"
$loginID = "ILLiadLink"

Write-Host "`n=== ILLiad ODBC Setup ===" -ForegroundColor Cyan
Write-Host "Enter ILLiadLink password:`n" -ForegroundColor Yellow

$securePassword = Read-Host "Password" -AsSecureString
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

if ([string]::IsNullOrWhiteSpace($plainPassword)) {
    Write-Host "✗ Password required" -ForegroundColor Red
    pause
    exit 1
}

# Detect Office
$officeArch = (Get-ItemProperty "HKLM:\Software\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue).Platform
$platform = if ($officeArch -eq "x64") { "64-bit" } else { "32-bit" }
$driverPath = if ($platform -eq "64-bit") { "C:\Windows\System32\sqlncli11.dll" } else { "C:\Windows\SysWOW64\sqlncli11.dll" }

Write-Host "Office: $platform" -ForegroundColor Green

# Remove old
Remove-OdbcDsn -Name $dsnName -DsnType System -Platform $platform -ErrorAction SilentlyContinue
Remove-OdbcDsn -Name $dsnName -DsnType User -Platform $platform -ErrorAction SilentlyContinue

# Create paths
$regPath = "HKLM:\SOFTWARE\ODBC\ODBC.INI\$dsnName"
$regListPath = "HKLM:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources"

$null = New-Item -Path "HKLM:\SOFTWARE\ODBC\ODBC.INI" -Force -ErrorAction SilentlyContinue
$null = New-Item -Path $regListPath -Force -ErrorAction SilentlyContinue
$null = New-Item -Path $regPath -Force

# Configure
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

foreach ($key in $settings.Keys) {
    Set-ItemProperty -Path $regPath -Name $key -Value $settings[$key] -Force
}

Set-ItemProperty -Path $regListPath -Name $dsnName -Value "SQL Server Native Client 11.0" -Force

$plainPassword = $null
[System.GC]::Collect()

Write-Host "`n✓ Configuration Complete!" -ForegroundColor Green
Write-Host "`nTest in Microsoft Access:" -ForegroundColor Yellow
Write-Host "  G:\Shared drives\Resource Sharing & Reserves\ILL" -ForegroundColor White
Write-Host "`nFirst connection may take 20-30 seconds." -ForegroundColor Gray

pause