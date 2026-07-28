<#
.SYNOPSIS
    Intune Win32 detection — "RESTART" shortcut on the Public Desktop.

.DESCRIPTION
    Detected     = stdout output + exit 0
    Not detected = no stdout + exit 1

    Verifies the target and arguments as well as the file's presence, so
    changing the shutdown.exe switches in the install script (e.g. adding /f)
    causes Intune to re-run the install rather than seeing a stale shortcut as
    already compliant.

.NOTES
    Author  : cmcleod1
    Date    : 2026-07-27
    Version : 1.0.0
    Pairs with Install-RestartShortcut.ps1 (system-context Win32 app).
#>
$shortcutName  = 'RESTART'
$expectedArgs  = '/r /t 0'

try {
    $publicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $shortcutPath  = Join-Path -Path $publicDesktop -ChildPath "$shortcutName.lnk"

    if (-not (Test-Path -LiteralPath $shortcutPath)) {
        exit 1
    }

    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
    $target   = [IO.Path]::GetFileName($shortcut.TargetPath)

    if ($target -eq 'shutdown.exe' -and $shortcut.Arguments.Trim() -eq $expectedArgs) {
        Write-Output 'Detected'
        exit 0
    }
    exit 1
}
catch {
    exit 1
}
