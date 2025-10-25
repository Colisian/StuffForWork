# Add Python 3.12 to System PATH
# This script runs silently in SYSTEM context via Intune

# Define the Python installation path
$pythonPath = "C:\Program Files\Python312"
$pythonScriptsPath = "C:\Program Files\Python312\Scripts"

# Log file for troubleshooting
$logPath = "C:\ProgramData\PythonPathInstall"
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
}
$logFile = "$logPath\install.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
}

Write-Log "Starting Python PATH installation"

# Function to add path to system environment variable
function Add-ToSystemPath {
    param([string]$PathToAdd)
    
    Write-Log "Processing path: $PathToAdd"
    
    if (-not (Test-Path $PathToAdd)) {
        Write-Log "WARNING: Path does not exist: $PathToAdd"
        return $false
    }
    
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    
    if ($currentPath -split ';' | Where-Object { $_ -eq $PathToAdd }) {
        Write-Log "Path already exists: $PathToAdd"
        return $true
    }
    
    $newPath = $currentPath + ";" + $PathToAdd
    [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    Write-Log "Successfully added to PATH: $PathToAdd"
    return $true
}

# Add Python paths
$result1 = Add-ToSystemPath -PathToAdd $pythonPath
$result2 = Add-ToSystemPath -PathToAdd $pythonScriptsPath

if ($result1 -or $result2) {
    Write-Log "Installation completed successfully"
    exit 0
} else {
    Write-Log "ERROR: Failed to add Python to PATH"
    exit 1
}