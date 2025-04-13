#Define regirstry path and values
$RegistryPath = "HKLM:\SOFTWARE\WOW6432Node\AtlasSystems\Illiad"
$ValueNames = "LogonSettingsPath"
$valueData = "C:\Program Files (x86)\Atlas Systems\Ares\Illiadlivelogon.dbc"

#Check if registry path exists
if (-not (Test-Path $RegistryPath)) {
    Write-Output "Registry path does not exist. Creating it..."
    #Create registry path if it does not exist
    New-Item -Path $RegistryPath -Force | Out-Null
}

#Update or Create the registry Value
try {
    Set-ItemProperty -Path $RegistryPath -Name $ValueNames -Value $valueData -Type String -Force
    Write-Output "Registry value updated successfully."
}
catch {
    Write-Output "Failed to update registry value: $_"
}
