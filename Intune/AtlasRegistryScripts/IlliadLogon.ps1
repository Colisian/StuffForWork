# File copy section

Write-Output "Starting Illiad Logon Script"

$destinationPath = "C:\Program Files (x86)\Illiad"
$sourceFolder = Join-Path -Path $PSScriptRoot -ChildPath "Files"
$filename = "Illiadlivelogon.dbc"
$sourceFile = Join-Path -Path $sourceFolder -ChildPath $filename
$destinationFile = Join-Path -Path $destinationPath -ChildPath $filename

if(-not (Test-Path -Path $destinationPath)) {
    Write-Output "Destination folder does not exist. Creating it..."
    try{
        New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
        Write-Output "Destination folder created successfully."
    }
    catch {
        Write-Output "Failed to create destination folder: $_"
        exit
    }
}

# Set permissions for Everyone on the Illiad directory
Write-Output "Setting permissions on $destinationPath..."
try {
    $acl = Get-Acl -Path $destinationPath
    
    # Define the access rule: Everyone with Modify rights
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Everyone",
        "Modify",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )
    
    # Add the access rule to the ACL
    $acl.SetAccessRule($accessRule)
    
    # Apply the modified ACL to the directory
    Set-Acl -Path $destinationPath -AclObject $acl
    
    Write-Output "Permissions set successfully. Everyone now has Modify access to $destinationPath"
}
catch {
    Write-Output "Failed to set permissions: $_"
}

# Check if the source file exists
if (-not(Test-Path -Path $sourceFile)) {
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

# Define registry path and values
$RegistryPath = "HKLM:\SOFTWARE\WOW6432Node\AtlasSystems\Illiad"
$ValueName = "LogonSettingsPath"
$valueData = "C:\Program Files (x86)\Illiad\Illiadlivelogon.dbc"

# Check if registry path exists
if (-not (Test-Path $RegistryPath)) {
    Write-Output "Registry path does not exist. Creating it..."
    # Create registry path if it does not exist
    try {
        New-Item -Path $RegistryPath -Force | Out-Null
        Write-Output "Registry path created successfully."
    }
    catch {
        Write-Output "Failed to create registry path: $_"
        exit
    }
}

# Update or Create the registry Value
try {
    Set-ItemProperty -Path $RegistryPath -Name $ValueName -Value $valueData -Type String -Force
    Write-Output "Registry value updated successfully."
}
catch {
    Write-Output "Failed to update registry value: $_"
}

Write-Output "Illiad Logon Script completed."