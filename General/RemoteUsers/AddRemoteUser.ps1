# Add the "Everyone" group to the Remote Desktop Users group
$groupToAdd = "Everyone"
Write-Host "Attempting to add $groupToAdd to the Remote Desktop Users group..."

# Attempt to add the Everyone group to the Remote Desktop Users group
try {
    Add-LocalGroupMember -Group "Remote Desktop Users" -Member $groupToAdd -ErrorAction Stop
    Write-Host "Successfully added $groupToAdd to the Remote Desktop Users group." -ForegroundColor Green
    exit 0
} catch {
    # Check if the error is because the member already exists
    if ($_.Exception.Message -like "*already a member*") {
        Write-Host "$groupToAdd is already a member of the Remote Desktop Users group." -ForegroundColor Yellow
        exit 0
    } else {
        Write-Host "Error adding $groupToAdd : $_" -ForegroundColor Red
        exit 1
    }
}
