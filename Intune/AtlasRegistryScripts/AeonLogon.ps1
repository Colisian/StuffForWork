# File copy section

Write-Output "Starting Aeon Logon Script"

$destinationPath = "C:\Program Files (x86)\Aeon"
$sourceFolder = Join-Path -Path $PSScriptRoot -ChildPath "Files"

# Define all files to copy
$filesToCopy = @(
    "AtlasHostingAE718.dbc",
    "AtlasHostingAE718_MDRM.dbc",
    "AtlasHostingAE718_MSPAL.dbc"
)

# Create destination folder if it doesn't exist
if(-not (Test-Path -Path $destinationPath)) {
    Write-Output "Destination folder does not exist. Creating it..."
    try {
        New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
        Write-Output "Destination folder created successfully."
    }
    catch {
        Write-Output "Failed to create destination folder: $_"
        exit
    }
}

# Copy each file
foreach ($filename in $filesToCopy) {
    $sourceFile = Join-Path -Path $sourceFolder -ChildPath $filename
    $destinationFile = Join-Path -Path $destinationPath -ChildPath $filename
    
    # Check if the source file exists
    if (-not (Test-Path -Path $sourceFile)) {
        Write-Output "Source file '$filename' does not exist. Skipping..."
        continue
    }
    
    try {
        Copy-Item -Path $sourceFile -Destination $destinationFile -Force
        Write-Output "File '$filename' copied successfully to $destinationPath"
    } 
    catch {
        Write-Output "Failed to copy file '$filename': $_"
    }
    
    # Verify the copy
    if (Test-Path -Path $destinationFile) {
        Write-Output "Verified: '$filename' exists at destination"
    } 
    else {
        Write-Output "Warning: '$filename' does not exist at destination"
    }
}

# Registry configuration section
$RegistryPath = "HKLM:\SOFTWARE\WOW6432Node\AtlasSystems\Aeon"
$ValueName = "LogonSettingsPath"
$valueData = "C:\Program Files (x86)\Aeon\AtlasHostingAE718.dbc"

# Check if registry path exists
if (-not (Test-Path $RegistryPath)) {
    Write-Output "Registry path does not exist. Creating it..."
    try {
        New-Item -Path $RegistryPath -Force | Out-Null
        Write-Output "Registry path created successfully."
    }
    catch {
        Write-Output "Failed to create registry path: $_"
        exit
    }
}

# Update or create the registry value
try {
    Set-ItemProperty -Path $RegistryPath -Name $ValueName -Value $valueData -Type String -Force
    Write-Output "Registry value updated successfully. Default set to: $valueData"
}
catch {
    Write-Output "Failed to update registry value: $_"
}

Write-Output "Aeon Logon Script completed."