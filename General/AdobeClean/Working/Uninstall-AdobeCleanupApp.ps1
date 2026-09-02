<#
.SYNOPSIS
    Uninstall-AdobeCleanupApp.ps1
    Uninstall action for the "Remove Adobe Creative Cloud Apps" Win32 app.

.DESCRIPTION
    This does NOT reinstall anything and does NOT touch any Adobe product. It
    removes only the detection sentinel written by Uninstall-AdobeProducts.ps1
    (HKLM\SOFTWARE\LIBR\AdobeUninstall).

    Why this exists:
      Intune verifies an uninstall by re-running the app's detection rule and
      expecting NOT-detected. Detect-AdobeUninstall.ps1 passes when the
      sentinel reads Completed=1 and no non-kept Adobe product is registered.
      If the Uninstall action ran the removal script again, the sentinel would
      be rewritten, detection would stay TRUE, and Intune would report the
      uninstall as failed forever. Clearing the sentinel makes detection go
      false, so the uninstall succeeds.

      Side benefit: it returns the app to a runnable state in Company Portal.
      Once the removal succeeds, detection blocks the Install button; a user
      who needs to re-run it (e.g. Adobe apps were reinstalled and left behind
      a partial state) can Uninstall then Install again.

    Removing the sentinel does not put any Adobe app back. Reinstall apps
    through the Creative Cloud desktop app or Patch My PC.

.PARAMETER LogPath
    Log directory. Default: C:\ProgramData\LIBR\Logs

.PARAMETER SentinelKey
    Registry key to remove. Must match $SentinelKey in
    Uninstall-AdobeProducts.ps1 and Detect-AdobeUninstall.ps1.

.EXAMPLE
    .\Uninstall-AdobeCleanupApp.ps1
    Clears the sentinel so Intune reports the uninstall as successful.

.NOTES
    Author  : Oji (cmcleod1)
    Date    : 2026-09-01
    Version : 1.0.0
    Run As  : SYSTEM (Intune) or local Administrator
    PS      : 5.1+ (7.x compatible)

    Exit codes:
      0 - Sentinel removed, or it was already absent
      1 - Not admin, or the sentinel could not be removed
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$LogPath = 'C:\ProgramData\LIBR\Logs',
    [string]$SentinelKey = 'HKLM:\SOFTWARE\LIBR\AdobeUninstall'
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.0.0'
$LogFile = Join-Path $LogPath "AdobeCleanupApp-Uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force -WhatIf:$false | Out-Null }

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $LogFile -Value $entry -WhatIf:$false   # logging is never a WhatIf-able change
    switch ($Level) {
        'ERROR'   { Write-Host $entry -ForegroundColor Red }
        'WARN'    { Write-Host $entry -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $entry -ForegroundColor Green }
        default   { Write-Host $entry }
    }
}

Write-Log '=============================================='
Write-Log "LIBR Adobe Cleanup App - Uninstall action v$ScriptVersion"
Write-Log "Computer : $env:COMPUTERNAME   User: $env:USERNAME"
Write-Log "Sentinel : $SentinelKey"
Write-Log 'NOTE: clears the detection sentinel only. No Adobe product is added or removed.'
Write-Log '=============================================='

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Log 'Must run as Administrator or SYSTEM. Exiting.' -Level ERROR; exit 1 }

if (-not (Test-Path $SentinelKey)) {
    Write-Log 'Sentinel not present - nothing to do (already uninstalled).' -Level SUCCESS
    exit 0
}

# Record what was there, so the log still shows the last removal run after the key is gone
try {
    $props = Get-ItemProperty -Path $SentinelKey -ErrorAction Stop
    Write-Log "Existing sentinel: Completed=$($props.Completed) Remaining=$($props.Remaining) ScriptVersion=$($props.ScriptVersion) LastRun=$($props.LastRun)"
}
catch { Write-Log "Could not read sentinel values: $_" -Level WARN }

if ($PSCmdlet.ShouldProcess($SentinelKey, 'Remove detection sentinel')) {
    try {
        Remove-Item -Path $SentinelKey -Recurse -Force -ErrorAction Stop
        Write-Log 'Sentinel removed - detection will now report not-detected.' -Level SUCCESS
    }
    catch {
        Write-Log "Failed to remove sentinel: $_" -Level ERROR
        exit 1
    }

    # Tidy up the parent LIBR key only if this script left it empty
    try {
        $parent = Split-Path $SentinelKey -Parent
        if ((Test-Path $parent) -and
            -not (Get-ChildItem $parent -ErrorAction SilentlyContinue) -and
            -not (Get-ItemProperty $parent -ErrorAction SilentlyContinue |
                  Get-Member -MemberType NoteProperty |
                  Where-Object { $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$' })) {
            Remove-Item -Path $parent -Force -ErrorAction Stop
            Write-Log "Removed now-empty parent key: $parent"
        }
    }
    catch { Write-Log "Parent key left in place: $_" -Level WARN }
}

Write-Log 'Uninstall action complete.' -Level SUCCESS
exit 0
