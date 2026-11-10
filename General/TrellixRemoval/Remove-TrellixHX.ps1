<#
.SYNOPSIS
    Silently uninstalls the Trellix (FireEye) Endpoint Security HX Agent (xagt).

.DESCRIPTION
    - Finds every installed HX agent through the Uninstall registry keys (32- and 64-bit),
      so it works no matter which agent version / MSI product code a device has.
    - By default, refuses to remove HX unless CrowdStrike Falcon is installed AND running,
      so a device is never left without EDR.
    - Supports the HX "Removal Protection Password" (UNINSTALL_PASSWORD MSI property).
    - Writes a transcript and a verbose MSI log to C:\ProgramData\UMDLibraries\TrellixRemoval\
      and scrubs the password out of the MSI log afterwards.

    Exit codes (Intune-friendly):
        0     = Removed, or HX was not present
        3010  = Removed, reboot required to finish
        1     = Failed (Falcon not running, MSI error, etc.)

.PARAMETER UninstallPassword
    HX Removal Protection Password. Leave empty if removal protection is disabled
    for the host set in the HX console (recommended - see README).

.PARAMETER SkipFalconCheck
    Remove HX even if CrowdStrike Falcon is not running. Use with care.

.PARAMETER DisplayNamePattern
    Regex used to match the agent in Add/Remove Programs. Change this only if your
    HX agents were deployed "disguised" under a custom name.

.PARAMETER CleanupFolders
    After a clean uninstall, delete leftover FireEye folders.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\Remove-TrellixHX.ps1

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\Remove-TrellixHX.ps1 -UninstallPassword 'P@ss' -CleanupFolders

.NOTES
    Run as SYSTEM (Intune) or elevated admin. Run in 64-bit PowerShell.
    Author: UMD Libraries ITFO
#>

[CmdletBinding()]
param(
    [string]$UninstallPassword = '',
    [switch]$SkipFalconCheck,
    [string]$DisplayNamePattern = 'FireEye Endpoint Agent|Endpoint Security \(HX\) Agent|^FireEye Agent$',
    [switch]$CleanupFolders
)

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------
$LogRoot   = 'C:\ProgramData\UMDLibraries\TrellixRemoval'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$Transcript = Join-Path $LogRoot "Remove-TrellixHX_$Stamp.log"

if (-not (Test-Path $LogRoot)) { New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null }
Start-Transcript -Path $Transcript -Force | Out-Null

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    Write-Output ("[{0}] [{1}] {2}" -f (Get-Date -Format 's'), $Level, $Message)
}

function Stop-Script {
    param([int]$Code)
    Write-Log "Exiting with code $Code"
    Stop-Transcript | Out-Null
    exit $Code
}

Write-Log "Starting Trellix/FireEye HX removal on $env:COMPUTERNAME"

# Warn if running in 32-bit PowerShell on a 64-bit OS (Intune default for some script types)
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    Write-Log "Running in 32-bit PowerShell. Registry checks still cover both views, but 64-bit is recommended." 'WARN'
}

# ---------------------------------------------------------------------------
# 1. Safety gate - make sure CrowdStrike Falcon is protecting the device
# ---------------------------------------------------------------------------
if (-not $SkipFalconCheck) {
    $falcon = Get-Service -Name 'CSFalconService' -ErrorAction SilentlyContinue
    if (-not $falcon -or $falcon.Status -ne 'Running') {
        Write-Log "CrowdStrike Falcon (CSFalconService) is not installed or not running. Aborting so the device is not left unprotected." 'ERROR'
        Stop-Script 1
    }
    Write-Log "CrowdStrike Falcon is running. Safe to continue."
} else {
    Write-Log "Falcon check skipped by -SkipFalconCheck." 'WARN'
}

# ---------------------------------------------------------------------------
# 2. Find HX agent installs in the Uninstall registry keys
# ---------------------------------------------------------------------------
$UninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$Found = Get-ItemProperty -Path $UninstallKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match $DisplayNamePattern }

if (-not $Found) {
    $svc = Get-Service -Name 'xagt' -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Log "No matching uninstall entry, but the 'xagt' service exists. The agent may be 'disguised' under a custom name - adjust -DisplayNamePattern." 'ERROR'
        Stop-Script 1
    }
    Write-Log "Trellix/FireEye HX agent not found. Nothing to do."
    Stop-Script 0
}

# ---------------------------------------------------------------------------
# 3. Uninstall each match via msiexec
# ---------------------------------------------------------------------------
$GuidRegex     = '\{[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}'
$SuccessCodes  = @(0, 1605, 1641, 3010)   # 1605 = already gone, 1641/3010 = reboot
$RebootNeeded  = $false
$AnyFailure    = $false

foreach ($app in $Found) {
    Write-Log "Found: '$($app.DisplayName)' version $($app.DisplayVersion)"

    # Product code is usually the registry key name; fall back to parsing UninstallString
    $ProductCode = $null
    if ($app.PSChildName -match "^$GuidRegex$") {
        $ProductCode = $app.PSChildName
    } elseif ($app.UninstallString -match $GuidRegex) {
        $ProductCode = $Matches[0]
    }

    if (-not $ProductCode) {
        Write-Log "Could not determine MSI product code for '$($app.DisplayName)'. UninstallString: $($app.UninstallString)" 'ERROR'
        $AnyFailure = $true
        continue
    }

    $MsiLog  = Join-Path $LogRoot "msiexec_${ProductCode}_$Stamp.log"
    $MsiArgs = "/x $ProductCode /qn /norestart REBOOT=ReallySuppress /l*v `"$MsiLog`""
    $SafeArgs = $MsiArgs   # version that is safe to print

    if ($UninstallPassword) {
        $MsiArgs  += " UNINSTALL_PASSWORD=`"$UninstallPassword`""
        $SafeArgs += ' UNINSTALL_PASSWORD="********"'
    }

    Write-Log "Running: msiexec.exe $SafeArgs"
    $proc = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $MsiArgs -Wait -PassThru -WindowStyle Hidden
    $code = $proc.ExitCode
    Write-Log "msiexec exit code: $code"

    # Scrub the password from the verbose MSI log in case the property was logged
    if ($UninstallPassword -and (Test-Path $MsiLog)) {
        try {
            $content = Get-Content -Path $MsiLog -Raw
            $content -replace [regex]::Escape($UninstallPassword), '********' | Set-Content -Path $MsiLog -Force
        } catch {
            Write-Log "Could not scrub password from $MsiLog : $_" 'WARN'
        }
    }

    switch ($code) {
        { $_ -in 1641, 3010 } { $RebootNeeded = $true }
        1603 { Write-Log "1603 = fatal MSI error. If removal protection is on, the password is missing or wrong. See $MsiLog" 'ERROR' }
        1618 { Write-Log "1618 = another install is in progress. Intune will retry." 'ERROR' }
    }

    if ($code -notin $SuccessCodes) { $AnyFailure = $true }
}

# ---------------------------------------------------------------------------
# 4. Verify and optionally clean up
# ---------------------------------------------------------------------------
Start-Sleep -Seconds 5
$svcAfter = Get-Service -Name 'xagt' -ErrorAction SilentlyContinue

if ($AnyFailure) {
    Write-Log "One or more uninstalls failed. Review logs in $LogRoot" 'ERROR'
    Stop-Script 1
}

if ($svcAfter) {
    Write-Log "xagt service still registered (status: $($svcAfter.Status)). A reboot should finish removal." 'WARN'
    $RebootNeeded = $true
}

if ($CleanupFolders -and -not $svcAfter) {
    foreach ($dir in @("${env:ProgramFiles(x86)}\FireEye", "$env:ProgramFiles\FireEye", "$env:ProgramData\FireEye")) {
        if (Test-Path $dir) {
            try {
                Remove-Item -Path $dir -Recurse -Force -ErrorAction Stop
                Write-Log "Removed leftover folder: $dir"
            } catch {
                Write-Log "Could not remove $dir (may clear after reboot): $($_.Exception.Message)" 'WARN'
            }
        }
    }
}

if ($RebootNeeded) {
    Write-Log "Trellix HX removed. Reboot required to complete."
    Stop-Script 3010
}

Write-Log "Trellix HX removed successfully."
Stop-Script 0