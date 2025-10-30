$msi = Join-Path $PSScriptRoot "SysAidAgent.msi"
Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart ACCOUNT=umlibraryitd SERVERURL=https://ticketing.lib.umd.edu SERIAL=770CAFF1ABC62952" -Wait
& "$PSScriptRoot\SysAidAgentFirewall.ps1"
