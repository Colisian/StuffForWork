$DekstopPath = "$env:Public\Desktop" 
$ShorcutName = "Alma Private Window"
$ShorcutPath = Join-Path -Path $DekstopPath -ChildPath "$ShorcutName.lnk"
$FirefoxPath = "C:\Program Files\Mozilla Firefox\private_browsing.exe"

#Url to open in the private window
$Url = "https://usmai-umcp.alma.exlibrisgroup.com/SAML"

#Create a WScript.Shell object to handle the shortcut creation
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShorcutPath)

#Set the target and arguments for the shortcut
$Shortcut.TargetPath = $FirefoxPath
$Shortcut.Arguments = $Url

#Save
$Shortcut.Save()