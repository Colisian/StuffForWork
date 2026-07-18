<#
.SYNOPSIS
    Intune Win32 detection — "LOG OFF" shortcut on the Public Desktop.

.DESCRIPTION
    Detected     = stdout output + exit 0
    Not detected = no stdout + exit 1

.NOTES
    Author  : cmcleod1
    Date    : 2026-07-18
    Version : 1.1.0
    Pairs with Install-LogOffShortcut.ps1 (system-context Win32 app).
#>
$shortcutName = 'LOG OFF'

try {
    $publicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $shortcutPath  = Join-Path -Path $publicDesktop -ChildPath "$shortcutName.lnk"

    if (Test-Path -LiteralPath $shortcutPath) {
        Write-Output 'Detected'
        exit 0
    }
    exit 1
}
catch {
    exit 1
}
