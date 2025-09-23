$TaskName = "GISLab Check-In Form Blocker"
$BaseDir  = "C:\ProgramData\GISLab\FormBlocker"

schtasks.exe /Delete /TN "$TaskName" /F | Out-Null 2>$null
Remove-Item -Path $BaseDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Uninstalled."
