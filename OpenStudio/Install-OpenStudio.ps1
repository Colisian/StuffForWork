# Install-OpenStudio.ps1
param(
  [string]$ZipPath  = "$PSScriptRoot\OpenStudio.zip",
  [string]$TargetDir = "C:\Program Files\OpenStudio"
)

# Remove any previous install
if (Test-Path $TargetDir) { Remove-Item $TargetDir -Recurse -Force }

# Extract the ZIP
Expand-Archive -Path $ZipPath -DestinationPath $TargetDir -Force

# (Optional) Create a desktop shortcut
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:PUBLIC\Desktop\OpenStudio.lnk")
$Shortcut.TargetPath = "$TargetDir\OpenStudio\bin\OpenStudioApp.exe"
$Shortcut.Save()