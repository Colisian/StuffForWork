# Remove-Python-From-Path-Advanced.ps1
# Removes all Python 3.12 related paths from System PATH

$logPath = "C:\ProgramData\PythonPathInstall"
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
}
$logFile = "$logPath\uninstall.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
}

Write-Log "Starting Python PATH removal"

# Get current system PATH
$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$pathArray = $currentPath -split ';'

# Define patterns to match Python 3.12 installations
$patternsToRemove = @(
    "C:\Program Files\Python312",
    "C:\Program Files\Python312\Scripts",
    "C:\Python312",
    "C:\Python312\Scripts"
)

# Filter out Python paths
$newPathArray = $pathArray | Where-Object {
    $currentItem = $_
    $shouldKeep = $true
    
    foreach ($pattern in $patternsToRemove) {
        if ($currentItem -eq $pattern) {
            Write-Log "Removing: $currentItem"
            $shouldKeep = $false
            break
        }
    }
    
    $shouldKeep -and $_ -ne ""
}

# Set the new PATH
$newPath = $newPathArray -join ';'
[Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")

Write-Log "Python paths removed from system PATH"
Write-Log "Uninstallation completed successfully"
exit 0