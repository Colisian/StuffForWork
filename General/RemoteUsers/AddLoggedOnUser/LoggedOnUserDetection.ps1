# Detection script for logged-on user in Remote Desktop Users group
# Returns exit 0 if current user is in the group, exit 1 if not

$logPath = "C:\PerfLogs\AddLoggedOnUser_Detection.log"
if (-not (Test-Path "C:\PerfLogs")) {
    New-Item -Path "C:\PerfLogs" -ItemType Directory -Force | Out-Null
}

# Function to get the currently logged-in user (works when running as SYSTEM)
function Get-LoggedOnUser {
    # Method 1: Try to get from Explorer process owner
    try {
        $explorer = Get-WmiObject -Class Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop | Select-Object -First 1
        if ($explorer) {
            $owner = $explorer.GetOwner()
            if ($owner.Domain -and $owner.User) {
                return "$($owner.Domain)\$($owner.User)"
            }
        }
    } catch { }

    # Method 2: Query user command
    try {
        $queryResult = query user 2>$null | Select-Object -Skip 1 | Select-Object -First 1
        if ($queryResult) {
            $username = ($queryResult -split '\s+')[0].TrimStart('>')
            $profiles = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" -ErrorAction SilentlyContinue
            foreach ($profile in $profiles) {
                $profilePath = (Get-ItemProperty $profile.PSPath).ProfileImagePath
                if ($profilePath -like "*$username*") {
                    $sid = $profile.PSChildName
                    try {
                        $objSID = New-Object System.Security.Principal.SecurityIdentifier($sid)
                        $objUser = $objSID.Translate([System.Security.Principal.NTAccount])
                        return $objUser.Value
                    } catch { }
                }
            }
            return $username
        }
    } catch { }

    # Method 3: Registry
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
        $lastUser = (Get-ItemProperty -Path $regPath -ErrorAction Stop).LastLoggedOnUser
        if ($lastUser) {
            return $lastUser
        }
    } catch { }

    return $null
}

# Get the logged-on user
$loggedOnUser = Get-LoggedOnUser

if (-not $loggedOnUser) {
    "$(Get-Date) - Detection: Could not determine logged-on user" | Out-File -FilePath $logPath -Encoding UTF8
    exit 1
}

# Get the Remote Desktop Users group members using ADSI
try {
    $remoteDesktopGroup = [ADSI]"WinNT://$env:COMPUTERNAME/Remote Desktop Users,group"
    $members = @($remoteDesktopGroup.Invoke("Members")) | ForEach-Object {
        $path = $_.GetType().InvokeMember("ADsPath", "GetProperty", $null, $_, $null)
        $path.Replace("WinNT://", "").Replace("/", "\")
    }
} catch {
    "$(Get-Date) - Detection: Error getting group members - $($_.Exception.Message)" | Out-File -FilePath $logPath -Encoding UTF8
    exit 1
}

# Check if the logged-on user is in the Remote Desktop Users group
# Need to handle various formats: AzureAD\user@domain.com, DOMAIN\user, etc.
$loggedOnUserNormalized = $loggedOnUser.ToLower()
$isCompliant = $false

foreach ($member in $members) {
    $memberNormalized = $member.ToLower()

    # Direct match
    if ($memberNormalized -eq $loggedOnUserNormalized) {
        $isCompliant = $true
        break
    }

    # Check if the username portion matches (after the \)
    $loggedOnUserPart = ($loggedOnUser -split '\\')[-1].ToLower()
    $memberPart = ($member -split '\\')[-1].ToLower()

    if ($loggedOnUserPart -eq $memberPart) {
        $isCompliant = $true
        break
    }
}

if ($isCompliant) {
    "$(Get-Date) - Detection SUCCESS: '$loggedOnUser' is a member of Remote Desktop Users" | Out-File -FilePath $logPath -Encoding UTF8
    Write-Host "User '$loggedOnUser' is a member of Remote Desktop Users group"
    exit 0
} else {
    "$(Get-Date) - Detection FAILED: '$loggedOnUser' is NOT a member of Remote Desktop Users" | Out-File -FilePath $logPath -Encoding UTF8
    Write-Host "User '$loggedOnUser' is NOT a member of Remote Desktop Users group"
    exit 1
}
