#Define registry path
$regpathSystem = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$regpathUser = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

# Function to set regirsty value
function Set-RegistryValue{
    param (
        [string]$path,
        [string]$name,
        [string]$value
    )
#Create registry if path does not exist
if (-not (Test-Path $path)) {
    New-Item -Path $path -Force
    }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType DWORD -Force
}

#Set the disable lock screen value to diasble Lock workstation at System Level
Set-RegistryValue -Path $regpathSystem -Name "DisableLockWorkstation" -Value 1 
#Set the disable lock screen value to diasble Lock workstation at User Level
Set-RegistryValue -Path $regpathUser -Name "DisableLockWorkstation" -Value 1

Get-ChildItem 'HKU:\' | ForEach-Object{
    try {
        $userRegPath = "HKU:\$($_.PSChildName)\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        Set-RegistryValue -Path $userRegPath -Name "DisableLockWorkstation" -Value 1
    } catch {
        Write-Output "Error: $($_.PSChildName)"
    }
}

# If you want to apply this to new users who log on, you can also set it in the Default User profile
$defaultUserRegPath = "HKU\.DEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-RegistryValue -path $defaultUserRegPath -Name "DisableLockWorkstation" -Value 1  
