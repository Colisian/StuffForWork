<#
.SYNOPSIS
    Removes the "LOG OFF" shortcut from the Public Desktop.

.DESCRIPTION
    Intune Win32 uninstall script. Runs non-interactively as SYSTEM.
    Deletes LOG OFF.lnk from the Public Desktop. Succeeds (exit 0) if the
    shortcut is already absent.

.NOTES
    Author  : cmcleod1
    Date    : 2026-07-18
    Version : 1.0.0
    Log     : C:\ProgramData\LogOffShortcut\Uninstall-LogOffShortcut.log
    Exit    : 0 = success, 1 = failure
#>
[CmdletBinding()]
param(
    [string]$ShortcutName = 'LOG OFF'
)

$ErrorActionPreference = 'Stop'

$logDir = 'C:\ProgramData\LogOffShortcut'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path (Join-Path $logDir 'Uninstall-LogOffShortcut.log') -Append

try {
    $publicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $shortcutPath  = Join-Path -Path $publicDesktop -ChildPath "$ShortcutName.lnk"

    if (Test-Path -LiteralPath $shortcutPath) {
        Write-Output "Removing shortcut: $shortcutPath"
        Remove-Item -LiteralPath $shortcutPath -Force -Confirm:$false
    }
    else {
        Write-Output "Shortcut not present at $shortcutPath — nothing to do."
    }

    Write-Output 'Uninstall complete.'
    exit 0
}
catch {
    Write-Error "Uninstall failed: $_"
    exit 1
}
finally {
    Stop-Transcript
}
