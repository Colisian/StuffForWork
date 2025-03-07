param (
    [string]$UserToKeep = "ad\cmcleod1",
    [string]$UserToAdd = "sach"
)

# Get the Remote Desktop Users group
$remoteDesktopGroup = [ADSI]"WinNT://$env:COMPUTERNAME/Remote Desktop Users,group"

# Get all members of the group
$members = @($remoteDesktopGroup.Invoke("Members")) | ForEach-Object {
    $path = $_.GetType().InvokeMember("ADsPath", "GetProperty", $null, $_, $null)
    $name = $path.Replace("WinNT://", "").Replace("/", "\")
    $name
}

# Display current members for verification
Write-Host "Current members of Remote Desktop Users group:"
$members | ForEach-Object { Write-Host "  $_" }

# Remove users except for the user to keep
foreach ($member in $members) {
    if ($member -ne $UserToKeep) {
        Write-Host "Removing $member from Remote Desktop Users group..."
        $memberPath = $member.Replace("\", "/")
        try {
            $remoteDesktopGroup.Remove("WinNT://$memberPath")
            Write-Host "Successfully removed $member."
        } catch {
            Write-Host "Error removing $member $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Keeping $member in Remote Desktop Users group."
    }
}

Write-Host "Operation completed."

# Add local admin account to Remote Desktop Users group
Write-Host "Adding $UserToAdd to Remote Desktop Users group..."
try {
    $remoteDesktopGroup.Add("WinNT://$env:COMPUTERNAME/$UserToAdd")
    Write-Host "Successfully added $UserToAdd to Remote Desktop Users group."
} catch {
    Write-Host "Error adding $UserToAdd to Remote Desktop Users group: $_" -ForegroundColor Red
}

# Verify the current members after changes
$updatedMembers = @($remoteDesktopGroup.Invoke("Members")) | ForEach-Object {
    $path = $_.GetType().InvokeMember("ADsPath", "GetProperty", $null, $_, $null)
    $name = $path.Replace("WinNT://", "").Replace("/", "\")
    $name
}

Write-Host "Updated members of Remote Desktop Users group:"
$updatedMembers | ForEach-Object { Write-Host "  $_" }