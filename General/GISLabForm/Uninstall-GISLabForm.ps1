$TaskName = "GIS Lab Check-In Helper"
$BaseDir  = "C:\ProgramData\GISLab\FormBlocker"

$errors = @()

# Remove scheduled task
$taskResult = schtasks.exe /Delete /TN "$TaskName" /F 2>&1
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) {
    # Exit code 1 means task doesn't exist, which is fine
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
        Write-Host "WARNING: $err" -ForegroundColor Yellow
    }
    Write-Host "GIS Lab Check-In Helper uninstalled with warnings." -ForegroundColor Yellow
    exit 0  # Still exit 0 since partial uninstall is acceptable
} else {
    Write-Host "GIS Lab Check-In Helper uninstalled successfully." -ForegroundColor Green
    exit 0
}
