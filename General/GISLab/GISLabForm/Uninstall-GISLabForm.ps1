<#
.SYNOPSIS
    Uninstalls the GIS Lab Check-In Helper.

.DESCRIPTION
    Stops any running launcher/kiosk instances, removes the scheduled task,
    and deletes the installation directory. Always exits 0 - a partial
    uninstall is acceptable and warnings are reported to the transcript.

.NOTES
    Author:  GIS Lab
    Date:    2026-07-10
    Version: 2.0
#>
[CmdletBinding()]
param()

$TaskName = 'GIS Lab Check-In Helper'
$BaseDir  = 'C:\ProgramData\GISLab\FormBlocker'
$errors   = @()

# Stop running launcher instances (any logged-on user) and their kiosk Edge windows
try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
        Where-Object { $_.CommandLine -match 'Launcher-GISLabForm\.ps1' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" -ErrorAction Stop |
        Where-Object { $_.CommandLine -match '--kiosk' -and $_.CommandLine -match 'lib-GIS-lab' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch {
    $errors += "Failed to stop running instances: $($_.Exception.Message)"
}

# Remove scheduled task (exit code 1 = task doesn't exist, which is fine)
$taskResult = schtasks.exe /Delete /TN "$TaskName" /F 2>&1
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) {
    $errors += "Failed to remove scheduled task: $taskResult"
}

# Remove files
if (Test-Path $BaseDir) {
    try {
        Remove-Item -Path $BaseDir -Recurse -Force -ErrorAction Stop
    } catch {
        $errors += "Failed to remove directory: $($_.Exception.Message)"
    }
}

# Report results
if ($errors.Count -gt 0) {
    foreach ($err in $errors) {
        Write-Host "WARNING: $err"
    }
    Write-Host 'GIS Lab Check-In Helper uninstalled with warnings.'
} else {
    Write-Host 'GIS Lab Check-In Helper uninstalled successfully.'
}
exit 0
