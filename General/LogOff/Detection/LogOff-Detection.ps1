# Intune Win32 detection — Public Desktop "LOG OFF" shortcut
$shortcutName = 'LOG OFF'

# Win32 apps run as SYSTEM; the shortcut lives on the Public desktop.
$desktopDir  = Join-Path -Path $env:PUBLIC -ChildPath 'Desktop'
$shortcutPath = Join-Path -Path $desktopDir -ChildPath "$shortcutName.lnk"

if (Test-Path -LiteralPath $shortcutPath) {
    Write-Output 'Detected'   # stdout present + exit 0 = DETECTED
    exit 0
}
else {
    exit 1                    # no stdout, non-zero = NOT detected
}