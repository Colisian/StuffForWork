# Define the location and name of the log file that indicates a successful configuration.
$logFilePath = "C:\PerfLogs\RemoteDesktopUsersDetection.log"

if (-not (Test-Path "C:\PerfLogs")) {
    New-Item -Path "C:\PerfLogs" -ItemType Directory -Force | Out-Null
}

# Get the Remote Desktop Users group using ADSI.
$remoteDesktopGroup = [ADSI]"WinNT://$env:COMPUTERNAME/Remote Desktop Users,group"

# Retrieve all current members of the group.
$members = @($remoteDesktopGroup.Invoke("Members")) | ForEach-Object {
    # Get the ADsPath property for each member.
    $path = $_.GetType().InvokeMember("ADsPath", "GetProperty", $null, $_, $null)
    # Format the path into a typical "ComputerName\Username" format.
    $name = $path.Replace("WinNT://", "").Replace("/", "\")
    $name
}

# Define the expected user that must be in the group.
# For a local account, the account is represented as 'ComputerName\Username'.
$expectedUser = "$env:COMPUTERNAME\sach"

# Check if the expected user is in the group.
if ($members -contains $expectedUser) {
    Write-Host "Detection successful: '$expectedUser' is a member of the Remote Desktop Users group."
    
    # Write a log file to signal that the configuration is correct.
    $logContent = "Detection successful: '$expectedUser' is a member of Remote Desktop Users group on $(Get-Date)."
    $logContent | Out-File -FilePath $logFilePath -Encoding UTF8

    # Exit with 0 (success) so that Intune detection sees this as compliant.
    exit 0
} else {
    Write-Host "Detection failed: '$expectedUser' is NOT a member of the Remote Desktop Users group."

    # Optionally, remove any stale log file if detection fails.
    if (Test-Path $logFilePath) {
        Remove-Item $logFilePath -Force
    }

    # Exit with 1 (failure) so that Intune detection reports non-compliance.
    exit 1
}
