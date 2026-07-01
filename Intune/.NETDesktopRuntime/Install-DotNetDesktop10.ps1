<#
.SYNOPSIS
    Installs .NET Desktop Runtime 10 (offline EXE) for Intune Win32 / SYSTEM context.
#>

$ErrorActionPreference = 'Stop'
$Installer = 'windowsdesktop-runtime-10.0.9-win-x64.exe'   # update on version bump
$LogDir    = "$env:ProgramData\IntuneLogs"
$IntuneLog = Join-Path $LogDir 'DotNetDesktop10-Install.log'   # our wrapper log
$MsLog     = Join-Path $LogDir 'DotNetDesktop10-MSI.log'       # installer's own log

if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message" | Tee-Object -FilePath $IntuneLog -Append
}

$exePath = Join-Path $PSScriptRoot $Installer
Write-Log "=== Installing $Installer ==="

if (-not (Test-Path $exePath)) {
    Write-Log "ERROR: Installer not found at $exePath"
    exit 1
}

# /install /quiet /norestart  +  bundle logging
$arguments = "/install /quiet /norestart /log `"$MsLog`""
Write-Log "Running: $exePath $arguments"

$proc = Start-Process -FilePath $exePath -ArgumentList $arguments -Wait -PassThru
$rc = $proc.ExitCode
Write-Log "Installer exit code: $rc"

# 0 = success | 3010 = success, reboot required | 1638/1641 also reboot-related
switch ($rc) {
    0     { Write-Log "Success."; exit 0 }
    3010  { Write-Log "Success, reboot required."; exit 3010 }
    1641  { Write-Log "Success, reboot initiated."; exit 3010 }
    default { Write-Log "FAILED with $rc"; exit $rc }
}