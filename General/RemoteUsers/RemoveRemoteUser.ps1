# Start transcript logging
$logPath = "C:\PerfLogs\RemoteUsers_Uninstall.log"
if (-not (Test-Path "C:\PerfLogs")) {
    New-Item -Path "C:\PerfLogs" -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path $logPath -Force

Write-Host "=== Remote Desktop Users Uninstall Script ==="
Write-Host "Running as: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Host "Architecture: $([Environment]::Is64BitProcess)"

# Remove the "Authenticated Users" group from the Remote Desktop Users group
$groupToRemove = "Authenticated Users"
Write-Host "Attempting to remove $groupToRemove from the Remote Desktop Users group..."

# Attempt to remove the group from the Remote Desktop Users group
try {
    Remove-LocalGroupMember -Group "Remote Desktop Users" -Member $groupToRemove -ErrorAction Stop
    Write-Host "Successfully removed $groupToRemove from the Remote Desktop Users group." -ForegroundColor Green
    Stop-Transcript
    exit 0
} catch {
    # Check if the error is because the member doesn't exist
    if ($_.Exception.Message -like "*not found*" -or $_.Exception.Message -like "*cannot find*") {
        Write-Host "$groupToRemove is not a member of the Remote Desktop Users group." -ForegroundColor Yellow
        Stop-Transcript
        exit 0
    } else {
        Write-Host "Error removing $groupToRemove : $_" -ForegroundColor Red
        Write-Host "Exception Type: $($_.Exception.GetType().FullName)"
        Write-Host "Exception Message: $($_.Exception.Message)"
        Stop-Transcript
        exit 1
    }
}