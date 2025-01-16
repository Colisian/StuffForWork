# Define dynamic paths to installation files
$ConnexionMsi = Join-Path -Path $PSScriptRoot -ChildPath "Connexion.msi"
$ComServiceMsi = Join-Path -Path $PSScriptRoot -ChildPath "OCLC.Connexion.ComServiceDeploy.msi"
$AccessDatabaseEngine = Join-Path -Path $PSScriptRoot -ChildPath "accessdatabaseengine_X64.exe"

# Check and install Connexion.msi
if (Test-Path $ConnexionMsi) {
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$ConnexionMsi`" ALLUSERS=1 /qn /norestart" -Wait
} else {
    Write-Host "Connexion.msi not found at $ConnexionMsi"
}

# Check and install OCLC.Connexion.ComServiceDeploy.msi
if (Test-Path $ComServiceMsi) {
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$ComServiceMsi`" ALLUSERS=1 /qn /norestart" -Wait
} else {
    Write-Host "OCLC.Connexion.ComServiceDeploy.msi not found at $ComServiceMsi"
}

# Check and install AccessDatabaseEngine
if (Test-Path $AccessDatabaseEngine) {
    Start-Process -FilePath $AccessDatabaseEngine -ArgumentList "/quiet /norestart" -Wait
} else {
    Write-Host "accessdatabaseengine_X64.exe not found at $AccessDatabaseEngine"
}
