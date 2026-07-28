<#
.SYNOPSIS
    Creates a "RESTART" shortcut on the Public Desktop for all users.

.DESCRIPTION
    Intune Win32 install script. Runs non-interactively as SYSTEM.
    Creates RESTART.lnk on the Public Desktop targeting shutdown.exe with
    /r /t 0 so any signed-in user can restart the machine with a double-click.

    Companion to the LOG OFF shortcut package (Intune\LogOff).

.PARAMETER ShortcutName
    Base name of the .lnk file. Defaults to 'RESTART'.

.PARAMETER Arguments
    Command line passed to shutdown.exe. Defaults to '/r /t 0' — restart now,
    without /f, so open applications get the normal "close and restart" prompt
    instead of losing unsaved work. Use '/r /t 0 /f' for a forced restart on
    kiosk/lab machines where nothing user-owned is running.

.NOTES
    Author  : cmcleod1
    Date    : 2026-07-27
    Version : 1.0.0
    Log     : C:\ProgramData\RestartShortcut\Install-RestartShortcut.log
    Exit    : 0 = success, 1 = failure
#>
[CmdletBinding()]
param(
    [string]$ShortcutName = 'RESTART',
    [string]$Arguments    = '/r /t 0'
)

$ErrorActionPreference = 'Stop'

$logDir = 'C:\ProgramData\RestartShortcut'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path (Join-Path $logDir 'Install-RestartShortcut.log') -Append

try {
    $publicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $shortcutPath  = Join-Path -Path $publicDesktop -ChildPath "$ShortcutName.lnk"

    Write-Output "Creating shortcut: $shortcutPath"
    $shell    = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath       = "$env:SystemRoot\System32\shutdown.exe"
    $shortcut.Arguments        = $Arguments
    $shortcut.WorkingDirectory = "$env:SystemRoot\System32"
    $shortcut.Description      = 'Restart this computer'
    # shell32.dll,238 = circular-arrow restart glyph on Windows 10/11.
    $shortcut.IconLocation     = "$env:SystemRoot\System32\shell32.dll,238"
    # Minimized so the shutdown.exe console window doesn't flash on screen.
    $shortcut.WindowStyle      = 7
    $shortcut.Save()

    if (-not (Test-Path -LiteralPath $shortcutPath)) {
        throw "Shortcut was not created at $shortcutPath"
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
