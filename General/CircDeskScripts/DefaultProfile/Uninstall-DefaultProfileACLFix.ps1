<#
.SYNOPSIS
    Intune Win32 app UNINSTALL script: rolls back the Default profile ACL fix.

.DESCRIPTION
    Runs as SYSTEM.

    Restores C:\Users\Default permissions from the OLDEST backup the install
    script made, which is the original state before the first fix.

    !!  WARNING  !!
    This puts the insecure permissions back: standard users will again be able
    to place files in the Default profile. Use it only to roll back if the fix
    breaks something.

    Quarantined files are NOT restored (they may contain personal data).
    Review them by hand in:
      C:\ProgramData\UMDLibraries\DefaultProfileACLFix\Quarantine\

    Remove the app from any REQUIRED assignment first. Otherwise detection
    reports "not installed" and Intune runs the install script again.

.NOTES
    Version : 1.0
    Exit    : 0 = success, 1 = failure
#>

#region --- Relaunch in 64-bit PowerShell if started from a 32-bit host ---
if ($env:PROCESSOR_ARCHITEW6432 -eq 'AMD64' -and $PSCommandPath) {
    $ps64 = Join-Path $env:WINDIR 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    & $ps64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}
#endregion

$ErrorActionPreference = 'Stop'

$ProfileRoot = 'C:\Users\Default'
$BaseDir     = 'C:\ProgramData\UMDLibraries\DefaultProfileACLFix'
$RegKey      = 'HKLM:\SOFTWARE\UMDLibraries\DefaultProfileACLFix'
$LogDir      = Join-Path $BaseDir 'Logs'
$BkpDir      = Join-Path $BaseDir 'Backups'
$LogFile     = Join-Path $LogDir ("Uninstall-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line } catch { }
}

function Invoke-Icacls {
    # Runs icacls.exe without letting its error text stop the script; output goes to the log.
    param([string[]]$Arguments)
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & icacls.exe @Arguments 2>&1
        $rc  = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $eap }
    foreach ($line in $out) {
        $text = "$line".Trim()
        if ($text) { Write-Log "  icacls: $text" }
    }
    return $rc
}

try {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    Write-Log "=== Default profile ACL ROLLBACK starting on $env:COMPUTERNAME ==="

    # Oldest backups = state before the first fix ran
    $rootBkp  = Get-ChildItem -LiteralPath $BkpDir -Filter 'RootACL-*.txt'  -ErrorAction SilentlyContinue |
                Sort-Object Name | Select-Object -First 1
    $childBkp = Get-ChildItem -LiteralPath $BkpDir -Filter 'ChildACL-*.txt' -ErrorAction SilentlyContinue |
                Sort-Object Name | Select-Object -First 1

    if (-not $rootBkp -or -not $childBkp) {
        Write-Log 'No backup files found. Nothing to restore.' 'WARN'
    }
    else {
        Write-Log "Restoring root from:     $($rootBkp.FullName)"
        Write-Log "Restoring children from: $($childBkp.FullName)"

        # icacls /restore applies saved paths relative to the folder given
        $parent = Split-Path $ProfileRoot -Parent
        $rc1 = Invoke-Icacls @($parent,      '/restore', $rootBkp.FullName,  '/C', '/Q')
        $rc2 = Invoke-Icacls @($ProfileRoot, '/restore', $childBkp.FullName, '/C', '/Q')
        Write-Log "icacls exit codes: root=$rc1 children=$rc2"
        if ($rc1 -ne 0 -or $rc2 -ne 0) {
            Write-Log 'Some items could not be restored (locked or missing). See above.' 'WARN'
        }
    }

    if (Test-Path $RegKey) { Remove-Item -Path $RegKey -Recurse -Force }
    Write-Log 'Removed registry marker.'
    Write-Log 'Quarantined files were NOT restored. Review them by hand if needed.' 'WARN'
    Write-Log '=== Rollback finished (exit 0) ==='
    exit 0
}
catch {
    Write-Log "Unexpected error: $($_.Exception.Message)" 'ERROR'
    exit 1
}