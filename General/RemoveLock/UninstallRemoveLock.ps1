#define registry path
$regpathSystem = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$regpathUser = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$defaultUserRegPath = "Registry::HKEY_USERS\.DEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

# Function to remove registry value
function Remove-ItemProperty{
    param (
        [string]$path,
        [string]$name
    )

if (Test-Path $path) {
    # Check if registry key exists 
    $property = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    if ($null -ne $property) {
        # Remove the DisableLockWorkstation
        Remove-ItemProperty -Path $path -Name "DisableLockWorkstation" -Force
        Write-Output "RemoveLock has been uninstalled successfully."
    } else {
        Write-Output "DisableLockWorkstation does not exist. RemoveLock is not installed"
        } 
    } 
}

# Remove the disable lock screen value to enable Lock workstation at System Level
Remove-RegistryValue -path $regpathSystem -name "DisableLockWorkstation"

# Remove the disable lock screen value to enable Lock workstation at User Level
Remove-RegistryValue -path $regpathUser -name "DisableLockWorkstation"

# Remove the disable lock screen value to enable Lock workstation at Default User Level
Remove-RegistryValue -path $defaultUserRegPath -name "DisableLockWorkstation"

try{
    $userSIDs = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" | ForEach-Object { $_.PSChildName }
   foreach ($userSID in $userSIDs){
    try {
        $userRegPath = "Registry::HKEY_USERS\$userSID\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        Remove-RegistryValue -path $userRegPath -name "DisableLockWorkstation"
    } catch {
        Write-Output "Error applying to User Profile ${userSID}: $($_.Exception.Message)"
        }

    } 
} catch {
    Write-Output "Error applying to User Profile ${userSID}: $($_.Exception.Message)"
}