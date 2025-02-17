$PublicDesktop = "C:\Users\Public\Desktop"
$AppFolder = "$PublicDesktop\Applications"

if (!(Test-Path $AppFolder)){
    New-Item -Path $PublicDesktop -Name "Applications" -ItemType Directory -Force
}

$ExcludedShortcuts = @(
    "Firefox.lnk",
    "Google Chrome.lnk",
    "Microsoft Edge.lnk"
)

$Shortcuts = Get-ChildItem -Path $PublicDesktop -Filter "*.lnk"

foreach ($shortcut in $shortcuts) {
    if ($ExcludedShortcuts -notcontains $shortcut.Name) {
        
        Move-Item -Path $Shortcut.Fullname -Destination $AppFolder -Force
        Write-Output "Moved $($Shortcut.Name) to $AppFolder"
    }
}
