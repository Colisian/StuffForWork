$ShortcutPath = "$env:Public\Desktop\Alma Private Window.lnk"

if (Test-Path $ShortcutPath) {
    Write-Output "Alma shortcut detected"
    exit 0
} else {
    exit 1
}
