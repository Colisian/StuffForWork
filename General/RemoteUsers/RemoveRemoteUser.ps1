# Remove the "Everyone" group from the Remote Desktop Users group
$groupToRemove = "Everyone"
Write-Host "Attempting to remove $groupToRemove from the Remote Desktop Users group..."

# Attempt to remove the Everyone group from the Remote Desktop Users group
try {
    Remove-LocalGroupMember -Group "Remote Desktop Users" -Member $groupToRemove -ErrorAction Stop
    Write-Host "Successfully removed $groupToRemove from the Remote Desktop Users group." -ForegroundColor Green
    exit 0
} catch {
    # Check if the error is because the member doesn't exist
    if ($_.Exception.Message -like "*not found*" -or $_.Exception.Message -like "*cannot find*") {
        Write-Host "$groupToRemove is not a member of the Remote Desktop Users group." -ForegroundColor Yellow
        exit 0
    } else {
        Write-Host "Error removing $groupToRemove : $_" -ForegroundColor Red
        exit 1
    }
}