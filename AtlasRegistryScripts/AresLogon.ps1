# File copy section

Write-Outut "Starting Ares Logon Script"

$destinationPath = "C:\Program Files (x86)\Ares"
$sourceFolder = Join-Path -Path $PSScriptRoot -ChildPath "Files"
$filename = "Areslivelogon.dbc"
$sourceFile = Join-Path -Path $sourceFolder -ChildPath $filename
$destinationFile = Join-Path -Path $destinationPath -ChildPath $filename

if(-not (Test-path -Path $destinationPath)) {
    Write-Output "Destination folder does not exist. Creating it..."
    try{
    New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
    }
    catch {
        Write-Output "Failed to create destination folder: $_"
    }
}

# Remove any existing file in the destination directory
if (Test-Path -Path $destinationFile) {
    Write-Output "Existing Areslivelogon.dbc found in destination. Removing it..."
    try {
        Remove-Item -Path $destinationFile -Force
        Write-Output "Existing file removed."
    } catch {
        Write-Output "Failed to remove existing file: $_"
    }
}

#Check if the source file exists
if (-not( Test-path -Path $sourceFile)) {
    Write-Output "Source file does not exist. Exiting..."
    exit
}

try{
    Copy-Item -Path $sourceFile -Destination $destinationFile -Force
    Write-Output "File copied successfully to $destinationFile"
} catch {
    Write-Output "Failed to copy file: $_"
}

if (Test-Path -Path $destinationFile) {
    Write-Output "File exists at $destinationFile"
} else {
    Write-Output "File does not exist at $destinationFile"
}


#Define regirstry path and values
$RegistryPath = "HKLM:\SOFTWARE\WOW6432Node\AtlasSystems\Ares"
$ValueNames = "LogonSettingsPath"
$valueData = "C:\Program Files (x86)\Ares\Areslivelogon.dbc"

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
