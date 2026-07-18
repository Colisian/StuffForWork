<#
.SYNOPSIS
    Creates a "LOG OFF" shortcut on the Public Desktop for all users.

.DESCRIPTION
    Intune Win32 install script. Runs non-interactively as SYSTEM.
    Creates LOG OFF.lnk on the Public Desktop targeting logoff.exe so any
    signed-in user can log off with a double-click.

    Also removes stale per-user copies of the shortcut left behind by the
    previous per-user deployment (including OneDrive-redirected desktops),
    so users don't end up with duplicates.

.NOTES
    Author  : cmcleod1
    Date    : 2026-07-18
    Version : 1.1.0
    Log     : C:\ProgramData\LogOffShortcut\Install-LogOffShortcut.log
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
Start-Transcript -Path (Join-Path $logDir 'Install-LogOffShortcut.log') -Append

try {
    $publicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $shortcutPath  = Join-Path -Path $publicDesktop -ChildPath "$ShortcutName.lnk"

    Write-Output "Creating shortcut: $shortcutPath"
    $shell    = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath       = "$env:SystemRoot\System32\logoff.exe"
    $shortcut.WorkingDirectory = "$env:SystemRoot\System32"
    $shortcut.Description      = 'Log off this computer'
    $shortcut.IconLocation     = "$env:SystemRoot\System32\shell32.dll,44"
    $shortcut.Save()

    if (-not (Test-Path -LiteralPath $shortcutPath)) {
        throw "Shortcut was not created at $shortcutPath"
    }

    # Clean up per-user copies from the old per-user deployment. Match any
    # "log off"-style name ("LOG OFF", "LogOff", "Log-Off", "Log_Off"), since
    # the original package's exact shortcut name is unknown. Desktops may be
    # redirected into OneDrive by Known Folder Move, so check both patterns.
    $userDesktops = Get-Item -Path 'C:\Users\*\Desktop', 'C:\Users\*\OneDrive*\Desktop' `
        -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $publicDesktop }

    foreach ($desktop in $userDesktops) {
        Write-Output "Scanning: $($desktop.FullName)"
        $staleShortcuts = Get-ChildItem -LiteralPath $desktop.FullName -Filter '*.lnk' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -match '^log[\s_-]?off$' }

        foreach ($stale in $staleShortcuts) {
            Write-Output "Removing stale per-user shortcut: $($stale.FullName)"
            Remove-Item -LiteralPath $stale.FullName -Force -Confirm:$false
        }
        if (-not $staleShortcuts) {
            Write-Output '  No stale shortcut found.'
        }
    }

    Write-Output 'Install complete.'
    exit 0
}
catch {
    Write-Error "Install failed: $_"
    exit 1
}
finally {
    Stop-Transcript
}
