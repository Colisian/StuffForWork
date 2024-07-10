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

if (Test-Path $regpath) {
    # Check if registry key exists 
    $property = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    if ($property) {
        # Remove the DisableLockWorkstation
        Remove-ItemProperty -Path $regpath -Name "DisableLockWorkstation" -Force
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

