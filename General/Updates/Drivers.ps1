Install-PackageProvider -Name NuGet -Force -Confirm:$false
Install-Module -Name PSWindowsUpdate -Force 
Get-WindowsUpdate
Install-WindowsUpdate -AcceptAll -AutoReboot -Force -IgnoreReboot -Install -Verbose