# Get the interactive user from the Win32_ComputerSystem WMI class.
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
$loggedInUser = $computerSystem.UserName

# Check if a user is logged in
if ([string]::IsNullOrEmpty($loggedInUser)) {
    Write-Error "No interactive user found. Ensure a user is logged in."
    exit 1
}

# Output the detected user for logging purposes.
Write-Host "Detected interactive user: $loggedInUser"

if($loggedInUser -match "\\") {
    Write-Host "Detected domain user: $loggedInUser"
    try{
        Add-LocalGroupMember -Group "Remote Desktop Users" -Member "AzureAD\$loggedInUser" -ErrorAction Stop
        Write-Host "Successfully added AzureAD\$loggedInUser to the Remote Desktop Users group."
    } Catch {
        Write-Error "Failed to add AzureAD\$loggedInUser to the Remote Desktop Users group. Error details: $_"
        exit 1
    }
} else {
# Attempt to add the interactive user to the Remote Desktop Users group.
try {
    Add-LocalGroupMember -Group "Remote Desktop Users" -Member $loggedInUser -ErrorAction Stop
    Write-Host "Successfully added $loggedInUser to the Remote Desktop Users group."
} catch {
    Write-Error "Failed to add $loggedInUser to the Remote Desktop Users group. Error details: $_"
    exit 1
    }
}