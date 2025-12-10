# Start transcript logging
$logPath = "C:\PerfLogs\RemoteUsers_Install.log"
if (-not (Test-Path "C:\PerfLogs")) {
    New-Item -Path "C:\PerfLogs" -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path $logPath -Force

Write-Host "=== Remote Desktop Users Install Script ==="
Write-Host "Running as: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Host "Architecture: $([Environment]::Is64BitProcess)"

# Add the "Authenticated Users" group to the Remote Desktop Users group
$groupToAdd = "Authenticated Users"
Write-Host "Attempting to add $groupToAdd to the Remote Desktop Users group..."

# Attempt to add the group to the Remote Desktop Users group
try {
    Add-LocalGroupMember -Group "Remote Desktop Users" -Member $groupToAdd -ErrorAction Stop
    Write-Host "Successfully added $groupToAdd to the Remote Desktop Users group." -ForegroundColor Green
    Stop-Transcript
    exit 0
} catch {
    # Check if the error is because the member already exists
    if ($_.Exception.Message -like "*already a member*") {
        Write-Host "$groupToAdd is already a member of the Remote Desktop Users group." -ForegroundColor Yellow
        Stop-Transcript
        exit 0
    } else {
        Write-Host "Error adding $groupToAdd : $_" -ForegroundColor Red
        Write-Host "Exception Type: $($_.Exception.GetType().FullName)"
        Write-Host "Exception Message: $($_.Exception.Message)"
        Stop-Transcript
        exit 1
    }
}