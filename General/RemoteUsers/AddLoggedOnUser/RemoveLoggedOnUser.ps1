# Start transcript logging
$logPath = "C:\PerfLogs\AddLoggedOnUser_Uninstall.log"
if (-not (Test-Path "C:\PerfLogs")) {
    New-Item -Path "C:\PerfLogs" -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path $logPath -Force

Write-Host "=== Remove Logged-On User from Remote Desktop Users ==="
Write-Host "Running as: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"

# Function to get the currently logged-in user (works when running as SYSTEM)
function Get-LoggedOnUser {
    # Method 1: Try to get from Explorer process owner (most reliable for interactive user)
    try {
        $explorer = Get-WmiObject -Class Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop | Select-Object -First 1
        if ($explorer) {
            $owner = $explorer.GetOwner()
            if ($owner.Domain -and $owner.User) {
                $username = "$($owner.Domain)\$($owner.User)"
                Write-Host "Found user via Explorer process: $username"
                return $username
            }
        }
    } catch {
        Write-Host "Explorer method failed: $($_.Exception.Message)"
    }

    # Method 2: Query user command
    try {
        $queryResult = query user 2>$null | Select-Object -Skip 1 | Select-Object -First 1
        if ($queryResult) {
            $username = ($queryResult -split '\s+')[0].TrimStart('>')
            Write-Host "Found user via query user: $username"
            $profiles = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" -ErrorAction SilentlyContinue
            foreach ($profile in $profiles) {
                $profilePath = (Get-ItemProperty $profile.PSPath).ProfileImagePath
                if ($profilePath -like "*$username*") {
                    $sid = $profile.PSChildName
                    try {
                        $objSID = New-Object System.Security.Principal.SecurityIdentifier($sid)
                        $objUser = $objSID.Translate([System.Security.Principal.NTAccount])
                        Write-Host "Resolved to: $($objUser.Value)"
                        return $objUser.Value
                    } catch {
                        Write-Host "Could not translate SID: $sid"
                    }
                }
            }
            return $username
        }
    } catch {
        Write-Host "Query user method failed: $($_.Exception.Message)"
    }

    # Method 3: Registry - LastLoggedOnUser
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
        $lastUser = (Get-ItemProperty -Path $regPath -ErrorAction Stop).LastLoggedOnUser
        if ($lastUser) {
            Write-Host "Found user via registry: $lastUser"
            return $lastUser
        }
    } catch {
        Write-Host "Registry method failed: $($_.Exception.Message)"
    }

    return $null
}

# Get the logged-on user
$loggedOnUser = Get-LoggedOnUser

if (-not $loggedOnUser) {
    Write-Host "ERROR: Could not determine logged-on user." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Write-Host "Logged-on user identified as: $loggedOnUser"

# Attempt to remove the user from the Remote Desktop Users group
try {
    Remove-LocalGroupMember -Group "Remote Desktop Users" -Member $loggedOnUser -ErrorAction Stop
    Write-Host "Successfully removed '$loggedOnUser' from the Remote Desktop Users group." -ForegroundColor Green

    # Remove the marker file
    $markerPath = "C:\PerfLogs\RDPUser_$($loggedOnUser -replace '\\','_' -replace '@','_').marker"
    if (Test-Path $markerPath) {
        Remove-Item $markerPath -Force
        Write-Host "Removed marker file: $markerPath"
    }

    Stop-Transcript
    exit 0
} catch {
    # Check if the error is because the member doesn't exist
    if ($_.Exception.Message -like "*not found*" -or $_.Exception.Message -like "*cannot find*" -or $_.Exception.Message -like "*was not found*") {
        Write-Host "'$loggedOnUser' is not a member of the Remote Desktop Users group." -ForegroundColor Yellow

        # Remove marker file if it exists
        $markerPath = "C:\PerfLogs\RDPUser_$($loggedOnUser -replace '\\','_' -replace '@','_').marker"
        if (Test-Path $markerPath) {
            Remove-Item $markerPath -Force
        }

        Stop-Transcript
        exit 0
    } else {
        Write-Host "Error removing '$loggedOnUser': $_" -ForegroundColor Red
        Write-Host "Exception Type: $($_.Exception.GetType().FullName)"
        Write-Host "Exception Message: $($_.Exception.Message)"
        Stop-Transcript
        exit 1
    }
}
