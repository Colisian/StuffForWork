<#
.SYNOPSIS
    Fixes folder redirection registry entries for the current user
.DESCRIPTION
    Removes registry entries pointing to network paths and restores default local paths
    Runs in USER context - targets HKEY_CURRENT_USER
.NOTES
    Designed for Intune Company Portal deployment (user-initiated install)
#>

param(
    [string]$LogPath = "$env:LOCALAPPDATA\FolderRedirectionFix\RegistryFix.log"
)

# Create log directory
$LogDir = Split-Path $LogPath -Parent
if (!(Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $LogMessage
}

function Fix-CurrentUserRegistry {
    Write-Log "Processing registry for current user: $env:USERNAME"
    
    $registryPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
    )
    
    # Default folder mappings - what they SHOULD be
    $defaultFolders = @{
        "Personal" = "%USERPROFILE%\Documents"
        "My Documents" = "%USERPROFILE%\Documents"
        "{374DE290-123F-4565-9164-39C4925E467B}" = "%USERPROFILE%\Downloads"
        "Desktop" = "%USERPROFILE%\Desktop"
        "My Pictures" = "%USERPROFILE%\Pictures"
        "My Music" = "%USERPROFILE%\Music"
        "My Video" = "%USERPROFILE%\Videos"
        "{F42EE2D3-909F-4907-8871-4C22FC0BF756}" = "%USERPROFILE%\Documents"
        "{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}" = "%USERPROFILE%\Downloads"
        "{33E28130-4E1E-4676-835A-98395C3BC3BB}" = "%USERPROFILE%\Pictures"
        "{4BD8D571-6D19-48D3-BE97-422220080E43}" = "%USERPROFILE%\Music"
        "{18989B1D-99B5-455B-841C-AB7C74E4DDFC}" = "%USERPROFILE%\Videos"
        "{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}" = "%USERPROFILE%\Desktop"
    }
    
    $changesFound = $false
    
    foreach ($regPathToCheck in $registryPaths) {
        Write-Log "Checking registry path: $regPathToCheck"
        
        if (Test-Path $regPathToCheck) {
            try {
                $regKey = Get-Item $regPathToCheck -ErrorAction Stop
                $valueNames = $regKey.GetValueNames()
                Write-Log "Found $($valueNames.Count) values in $regPathToCheck"
                
                foreach ($valueName in $valueNames) {
                    # Only process values we have mappings for
                    if ($defaultFolders.ContainsKey($valueName)) {
                        try {
                            $currentValue = $regKey.GetValue($valueName)
                            $expectedValue = $defaultFolders[$valueName]
                            
                            Write-Log "Checking: $valueName = '$currentValue' (Expected: '$expectedValue')"
                            
                            # Check if current value needs to be fixed
                            $needsUpdate = $false
                            $reason = ""
                            
                            if ([string]::IsNullOrEmpty($currentValue)) {
                                $reason = "Value is empty"
                                $needsUpdate = $true
                            }
                            elseif ($currentValue -ne $expectedValue) {
                                # Value doesn't match expected - check if it's a UNC path, network drive, or incorrect path
                                $currentValueStr = $currentValue.ToString()
                                
                                # Check for UNC network paths (\\server\share)
                                if ($currentValueStr -match '^\\\\') {
                                    $reason = "UNC network path detected"
                                    $needsUpdate = $true
                                }
                                # Check for mapped network drives (not C:\Users)
                                elseif ($currentValueStr -match '^[A-Z]:' -and $currentValueStr -notmatch '^C:\\Users') {
                                    $reason = "Network drive mapping detected"
                                    $needsUpdate = $true
                                }
                                # Check if it's a hardcoded C:\Users path without %USERPROFILE%
                                elseif ($currentValueStr -notmatch '%USERPROFILE%' -and $currentValueStr -match '^C:\\Users\\[^\\]+\\(Documents|Desktop|Pictures|Music|Videos|Downloads)') {
                                    $reason = "Hardcoded path without %USERPROFILE%"
                                    $needsUpdate = $true
                                }
                                # Check if path doesn't exist or is inaccessible (for non-%USERPROFILE% paths)
                                elseif ($currentValueStr -notmatch '%USERPROFILE%' -and $currentValueStr -notmatch '^C:\\Users') {
                                    $expandedPath = [Environment]::ExpandEnvironmentVariables($currentValueStr)
                                    if (!(Test-Path $expandedPath -ErrorAction SilentlyContinue)) {
                                        $reason = "Path is inaccessible"
                                        $needsUpdate = $true
                                    }
                                }
                            }
                            
                            if ($needsUpdate) {
                                $changesFound = $true
                                Write-Log "NEEDS UPDATE: $valueName - Reason: $reason - Current: '$currentValue' -> New: '$expectedValue'" "WARNING"
                                Set-ItemProperty -Path $regPathToCheck -Name $valueName -Value $expectedValue -Force
                                Write-Log "UPDATED: $valueName to '$expectedValue'" "SUCCESS"
                            } else {
                                Write-Log "OK: $valueName is already correct"
                            }
                        }
                        catch {
                            Write-Log "Error processing value $valueName : $($_.Exception.Message)" "ERROR"
                        }
                    }
                }
            }
            catch {
                Write-Log "Error accessing registry path $regPathToCheck : $($_.Exception.Message)" "ERROR"
            }
        } else {
            Write-Log "Registry path does not exist: $regPathToCheck" "WARNING"
        }
    }
    
    return $changesFound
}

function Restart-ExplorerProcess {
    Write-Log "Attempting to restart Windows Explorer to apply changes..."
    
    try {
        # Get current user's explorer processes
        $explorerProcesses = Get-Process -Name explorer -ErrorAction SilentlyContinue
        
        if ($explorerProcesses) {
            Write-Log "Restarting Explorer for current user"
            
            # Stop explorer
            Stop-Process -Name explorer -Force -ErrorAction Stop
            
            Write-Log "Stopped Explorer process" "SUCCESS"
            
            # Wait a moment
            Start-Sleep -Milliseconds 500
            
            # Check if it auto-restarted
            $newExplorer = Get-Process -Name explorer -ErrorAction SilentlyContinue
            
            if ($newExplorer) {
                Write-Log "Explorer auto-restarted successfully" "SUCCESS"
            } else {
                Write-Log "Explorer did not auto-restart, starting manually..."
                Start-Process explorer.exe
                Write-Log "Explorer started manually" "SUCCESS"
            }
        }
        else {
            Write-Log "No Explorer process found (unexpected)" "WARNING"
        }
    }
    catch {
        Write-Log "Error restarting Explorer: $($_.Exception.Message)" "ERROR"
        # Try to start Explorer anyway if it crashed
        try {
            Start-Process explorer.exe -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "Could not start Explorer manually" "ERROR"
        }
    }
}

function Ensure-LocalFoldersExist {
    Write-Log "Ensuring local user folders exist..."
    
    $folders = @(
        [Environment]::GetFolderPath("MyDocuments"),
        [Environment]::GetFolderPath("Desktop"),
        [Environment]::GetFolderPath("MyPictures"),
        [Environment]::GetFolderPath("MyMusic"),
        [Environment]::GetFolderPath("MyVideos")
    )
    
    foreach ($folder in $folders) {
        if ($folder -and !(Test-Path $folder)) {
            try {
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
                Write-Log "Created folder: $folder" "SUCCESS"
            }
            catch {
                Write-Log "Error creating folder $folder : $($_.Exception.Message)" "ERROR"
            }
        }
    }
}

# Main execution
Write-Log "=== Starting Registry Fix Installation (User Context) ==="
Write-Log "Current user: $env:USERNAME"
Write-Log "Computer name: $env:COMPUTERNAME"
Write-Log "User profile: $env:USERPROFILE"

try {
    # Step 1: Fix registry entries
    Write-Log "Step 1: Fixing registry folder redirection entries"
    $changesFound = Fix-CurrentUserRegistry
    
    if ($changesFound) {
        Write-Log "Registry changes were made" "SUCCESS"
        
        # Step 2: Ensure local folders exist
        Write-Log "Step 2: Ensuring local folders exist"
        Ensure-LocalFoldersExist
        
        # Step 3: Restart Explorer
        Write-Log "Step 3: Restarting Windows Explorer to apply changes"
        Restart-ExplorerProcess
        
        # Create success marker file
        $markerFile = "$LogDir\FixApplied.txt"
        Set-Content -Path $markerFile -Value (Get-Date).ToString()
        
        Write-Log "=== Registry fix completed successfully! ===" "SUCCESS"
        exit 0
    }
    else {
        Write-Log "No registry changes were needed - all values are correct" "INFO"
        
        # Create success marker file anyway
        $markerFile = "$LogDir\FixApplied.txt"
        Set-Content -Path $markerFile -Value (Get-Date).ToString()
        
        Write-Log "=== Registry fix completed (no changes needed) ===" "SUCCESS"
        exit 0
    }
}
catch {
    Write-Log "Critical error: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
