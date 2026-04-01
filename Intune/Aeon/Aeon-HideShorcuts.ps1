Start-Sleep -Seconds 20

$publicDesktop = "C:\Users\Public\Desktop"

$Shortcuts = @(
    "Customization Manager.lnk",
    "Staff Manager.lnk"
)

foreach ($shortcut in $Shortcuts){
    $shortcutPath = Join-Path -Path $publicDesktop -ChildPath $shortcut
    if (Test-Path $shortcutPath){
        Remove-Item -Path $shortcutPath -Force
        Write-Output "Removed $shortcutPath"
    }
}

Write-Output "Shortcuts removed" 