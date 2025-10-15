# =============================================================================
# FILE 1: Install-RegistryFix.ps1
# This is the main installation 
# =============================================================================

<#
.SYNOPSIS
    Fixes folder redirection registry entries pointing to old server
.DESCRIPTION
    Removes registry entries pointing to Z: drive and restores default local paths
    Runs in SYSTEM context but fixes registry for all logged-in users
.NOTES
    Designed for Intune Win32 app deployment
#>

param(
    [string]$LogPath = "$env:ProgramData\FolderRedirectionFix\RegistryFix.log"
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

function Get-LoggedInUsers {
    try {
        $users = @()
        $explorerProcesses = Get-WmiObject Win32_Process -Filter "Name = 'explorer.exe'"
        
        foreach ($process in $explorerProcesses) {
            $owner = $process.GetOwner()
            $username = "$($owner.Domain)\$($owner.User)"
            if ($username -notin $users) {
                $users += $username
            }
        }
        return $users
    }
    catch {
        Write-Log "Error getting logged in users: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

function Get-UserSID {
    param([string]$Username)
    
    try {
        $objUser = New-Object System.Security.Principal.NTAccount($Username)
        $sid = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
        return $sid.Value
    }
    catch {
        Write-Log "Error getting SID for $Username : $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Fix-UserRegistry {
    param(
        [string]$UserSID,
        [string]$Username
    )
    
    Write-Log "Processing registry for user: $Username (SID: $UserSID)"
    
    # Load the user's registry hive if not already loaded
    $userHiveLoaded = $false
    $regPath = "Registry::HKEY_USERS\$UserSID"
    
    if (!(Test-Path $regPath)) {
        Write-Log "User hive not loaded, attempting to load..." "WARNING"
        # Hive not loaded - this user is not currently logged in
        # We'll skip for now, but log it
        return $false
    }
    
    $registryPaths = @(
        "$regPath\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders",
        "$regPath\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
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
        if (Test-Path $regPathToCheck) {
            try {
                $regKey = Get-Item $regPathToCheck -ErrorAction Stop
                
                foreach ($valueName in $regKey.GetValueNames()) {
                    # Only process values we have mappings for
                    if ($defaultFolders.ContainsKey($valueName)) {
                        try {
                            $currentValue = $regKey.GetValue($valueName)
                            $expectedValue = $defaultFolders[$valueName]
                            
                            # Check if current value needs to be fixed
                            $needsUpdate = $false
                            
                            if ([string]::IsNullOrEmpty($currentValue)) {
                                Write-Log "Value $valueName is empty, will set to: $expectedValue"
                                $needsUpdate = $true
                            }
                            elseif ($currentValue -ne $expectedValue) {
                                # Value doesn't match expected - check if it's a UNC path, network drive, or incorrect path
                                $currentValueStr = $currentValue.ToString()
                                
                                # Check for network paths (UNC or mapped drives)
                                if ($currentValueStr -match '^\\\\' -or $currentValueStr -match '^[A-Z]:' -and $currentValueStr -notmatch '^C:\\Users') {
                                    Write-Log "Found network/redirected path for $Username : $valueName = $currentValue"
                                    $needsUpdate = $true
                                }
                                # Check if it's missing %USERPROFILE% variable
                                elseif ($currentValueStr -notmatch '%USERPROFILE%' -and $currentValueStr -match '^C:\\Users\\[^\\]+\\(Documents|Desktop|Pictures|Music|Videos|Downloads)') {
                                    Write-Log "Found hardcoded path for $Username : $valueName = $currentValue"
                                    $needsUpdate = $true
                                }
                                # Check if path doesn't exist or is inaccessible
                                elseif ($currentValueStr -notmatch '%USERPROFILE%') {
                                    $expandedPath = [Environment]::ExpandEnvironmentVariables($currentValueStr)
                                    if (!(Test-Path $expandedPath -ErrorAction SilentlyContinue)) {
                                        Write-Log "Found inaccessible path for $Username : $valueName = $currentValue"
                                        $needsUpdate = $true
                                    }
                                }
                            }
                            
                            if ($needsUpdate) {
                                $changesFound = $true
                                Set-ItemProperty -Path $regPathToCheck -Name $valueName -Value $expectedValue -Force
                                Write-Log "Updated $valueName from '$currentValue' to: $expectedValue" "SUCCESS"
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
        }
    }
    
    return $changesFound
}

# Main execution
Write-Log "=== Starting Registry Fix Installation ==="

$totalChanges = 0

try {
    # Get all user profiles
    $userProfiles = Get-WmiObject Win32_UserProfile | Where-Object { 
        $_.Special -eq $false -and 
        $_.LocalPath -notlike "*system32*" -and
        $_.LocalPath -notlike "*systemprofile*"
    }
    
    Write-Log "Found $($userProfiles.Count) user profiles to check"
    
    foreach ($profile in $userProfiles) {
        $sid = $profile.SID
        
        # Try to get username from SID
        try {
            $objSID = New-Object System.Security.Principal.SecurityIdentifier($sid)
            $objUser = $objSID.Translate([System.Security.Principal.NTAccount])
            $username = $objUser.Value
        }
        catch {
            $username = "Unknown"
            Write-Log "Could not resolve username for SID: $sid" "WARNING"
        }
        
        Write-Log "Checking profile: $username"
        
        $changesFound = Fix-UserRegistry -UserSID $sid -Username $username
        
        if ($changesFound) {
            $totalChanges++
        }
    }
    
    # Create success marker file
    $markerFile = "$LogDir\FixApplied.txt"
    Set-Content -Path $markerFile -Value (Get-Date).ToString()
    
    Write-Log "=== Registry fix completed. Changes made to $totalChanges user profiles ===" "SUCCESS"
    
    if ($totalChanges -gt 0) {
        exit 0  # Success with changes
    }
    else {
        Write-Log "No changes were needed" "INFO"
        exit 0  # Success, no changes needed
    }
}
catch {
    Write-Log "Critical error: $($_.Exception.Message)" "ERROR"
    exit 1  # Failure
}


