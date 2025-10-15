<#
.SYNOPSIS
    Detection script for folder redirection registry fix
.DESCRIPTION
    Checks if registry entries still point to old server drive
    Returns exit code 0 if fix is applied, 1 if fix is needed
#>

param(
    [string]$OldServerDrive = "Z:",
    [string]$MarkerFile = "$env:ProgramData\FolderRedirectionFix\FixApplied.txt"
)

# Check if marker file exists (indicating fix was previously applied)
if (Test-Path $MarkerFile) {
    Write-Output "Fix already applied on: $(Get-Content $MarkerFile)"
    exit 0
}

# If no marker, check if any user profiles still have the issue
$issueFound = $false

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
                            $value = $regKey.GetValue($valueName)
                            if ($value -and $value.ToString().StartsWith($OldServerDrive)) {
                                Write-Output "Found registry entry pointing to $OldServerDrive"
                                $issueFound = $true
                                break
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
