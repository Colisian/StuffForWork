<#
.SYNOPSIS
    Detection script for folder redirection registry fix
.DESCRIPTION
    Checks if registry entries are properly set to %USERPROFILE% paths
    Returns exit code 0 if fix is applied, 1 if fix is needed
#>

param(
    [string]$MarkerFile = "$env:ProgramData\FolderRedirectionFix\FixApplied.txt"
)

# Check if marker file exists (indicating fix was previously applied)
if (Test-Path $MarkerFile) {
    Write-Output "Fix already applied on: $(Get-Content $MarkerFile)"
    exit 0
}

# If no marker, check if any user profiles still have issues
$issueFound = $false

# Define what the values SHOULD be
$expectedValues = @{
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

try {
    $userProfiles = Get-WmiObject Win32_UserProfile | Where-Object { 
        $_.Special -eq $false -and 
        $_.LocalPath -notlike "*system32*" -and
        $_.LocalPath -notlike "*systemprofile*"
    }
    
    foreach ($profile in $userProfiles) {
        $sid = $profile.SID
        $regPath = "Registry::HKEY_USERS\$sid"
        
        if (Test-Path $regPath) {
            $pathsToCheck = @(
                "$regPath\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders",
                "$regPath\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
            )
            
            foreach ($path in $pathsToCheck) {
                if (Test-Path $path) {
                    $regKey = Get-Item $path -ErrorAction SilentlyContinue
                    if ($regKey) {
                        foreach ($valueName in $regKey.GetValueNames()) {
                            # Only check values we care about
                            if ($expectedValues.ContainsKey($valueName)) {
                                $currentValue = $regKey.GetValue($valueName)
                                $expectedValue = $expectedValues[$valueName]
                                
                                if ($currentValue) {
                                    $currentValueStr = $currentValue.ToString()
                                    
                                    # Check if value needs fixing
                                    if ($currentValueStr -ne $expectedValue) {
                                        # Check for network paths, hardcoded paths, or missing %USERPROFILE%
                                        if ($currentValueStr -match '^\\\\' -or 
                                            ($currentValueStr -match '^[A-Z]:' -and $currentValueStr -notmatch '^C:\\Users') -or
                                            ($currentValueStr -notmatch '%USERPROFILE%' -and $currentValueStr -match '^C:\\Users\\[^\\]+\\(Documents|Desktop|Pictures|Music|Videos|Downloads)')) {
                                            Write-Output "Found misconfigured registry entry: $valueName = $currentValueStr"
                                            $issueFound = $true
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if ($issueFound) { break }
            }
        }
        if ($issueFound) { break }
    }
    
    if ($issueFound) {
        Write-Output "Registry fix needed"
        exit 1  # Not detected, needs installation
    }
    else {
        Write-Output "No issues found"
        exit 0  # Detected, no installation needed
    }
}
catch {
    Write-Output "Error during detection: $($_.Exception.Message)"
    exit 1  # Error, assume fix is needed
}
