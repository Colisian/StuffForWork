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

# Define paths
$TargetExe = "C:\Program Files\OCLC\Connexion\Program\Connex.exe"
$ShortcutPath = "C:\Users\Public\Desktop\Connexion.lnk"

# Create the shortcut
if (Test-Path -Path $TargetExe) {
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $TargetExe
    $Shortcut.WorkingDirectory = "C:\Program Files\OCLC\Connexion\Program"
    $Shortcut.WindowStyle = 1 # Normal window
    $Shortcut.IconLocation = "$TargetExe, 0" # Use the app's icon
    $Shortcut.Save()
    Write-Host "Shortcut created successfully at $ShortcutPath"
} else {
    Write-Host "Executable not found at $TargetExe. Shortcut not created."
}