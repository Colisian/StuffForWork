$DesktopPath = "$env:Public\Desktop"
$ShortcutName = "Alma Private Window"
$ShortcutPath = Join-Path -Path $DesktopPath -ChildPath "$ShortcutName.lnk"
$FirefoxPath = "C:\Program Files\Mozilla Firefox\private_browsing.exe"

#Url to open in the private window
$Url = "https://usmai-umcp.alma.exlibrisgroup.com/SAML"

#Create a WScript.Shell object to handle the shortcut creation
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)

#Set the target and arguments for the shortcut
$Shortcut.TargetPath = $FirefoxPath
$Shortcut.Arguments = $Url

#Save
$Shortcut.Save()