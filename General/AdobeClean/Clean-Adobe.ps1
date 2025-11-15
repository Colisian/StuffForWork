<# 
.SYNOPSIS
  Removes Adobe directories from all user profiles on a machine.

.DESCRIPTION
  For every folder under C:\Users, this script removes:
    C:\Users\<username>\AppData\Roaming\Adobe
    C:\Users\<username>\AppData\Local\Adobe
    C:\Users\<username>\AppData\LocalLow\Adobe

  Designed to be run as Administrator or SYSTEM (e.g. via Intune).
#>

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $logRoot = "C:\ProgramData\AdobeCleanup"
    $logFile = Join-Path $logRoot "AdobeUserCleanup.log"

    if (-not (Test-Path $logRoot)) {
        New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $entry
    Write-Output $entry
}

function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-AdobeUserFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserProfilePath,   # e.g. 'C:\Users\jdoe'
        [Parameter(Mandatory = $true)]
        [string]$SubPath            # e.g. 'AppData\Roaming'
    )

    $basePath = Join-Path $UserProfilePath $SubPath
    $target   = Join-Path $basePath "Adobe"

    if (Test-Path -LiteralPath $target) {
        try {
            Write-Log "Removing Adobe folder: $target"
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
            Write-Log "Successfully removed: $target"
        }
        catch {
            Write-Log "FAILED to remove: $target. Error: $($_.Exception.Message)" "ERROR"
        }
    }
    else {
        Write-Log "Not found (skipping): $target"
    }
}

#endregion Helper Functions

#region Pre-checks

if (-not (Test-IsAdmin)) {
    Write-Log "Script must be run as Administrator or SYSTEM. Exiting." "ERROR"
    throw "Not running with administrative privileges."
}

Write-Log "===== Starting Adobe user profile directory cleanup ====="

#endregion Pre-checks

#region Stop common Adobe processes (optional but helps unlock files)

$adobeProcesses = @(
    "Acrobat",
    "AcroCEF",
    "AcroTray",
    "AdobeIPCBroker",
    "AdobeCollabSync",
    "AdobeARM",
    "CCXProcess",
    "Creative Cloud",
    "Adobe Desktop Service"
)

foreach ($proc in $adobeProcesses) {
    try {
        Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Log "Stopping process: $($_.ProcessName) (Id=$($_.Id))"
            $_ | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Log "Error stopping process ${proc}: $($_.Exception.Message)" "ERROR"
    }
}

#endregion Stop processes

#region Remove Adobe folders from ALL user profiles

$userRoot = "C:\Users"

if (Test-Path $userRoot) {
    Get-ChildItem -Path $userRoot -Directory | ForEach-Object {
        $userProfile = $_.FullName
        Write-Log "Processing user profile: $userProfile"

        Remove-AdobeUserFolder -UserProfilePath $userProfile -SubPath "AppData\Roaming"
        Remove-AdobeUserFolder -UserProfilePath $userProfile -SubPath "AppData\Local"
        Remove-AdobeUserFolder -UserProfilePath $userProfile -SubPath "AppData\LocalLow"
    }
}
else {
    Write-Log "User root folder not found: $userRoot" "ERROR"
}

#endregion Remove Adobe folders from ALL user profiles

Write-Log "===== Adobe user profile directory cleanup complete ====="