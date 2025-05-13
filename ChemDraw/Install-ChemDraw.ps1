# 1.Install VC++
Start-Process -FilePath "$PSScriptRoot\vcredist_x64.exe" `
    -ArgumentList "/quiet /norestart" `
    -Wait

# 2. Install WebVView2 Runtime
Start-Process -FilePath "$PSScriptRoot\MicrosoftEdgeWebView2RuntimeInstallerX64.exe" `
    -ArgumentList "/silent /install" `
    -Wait


# 3. Install ChemDraw MSI
Start-Process -FilePath "msiexec.exe" `
  -ArgumentList '/i', "`"$PSScriptRoot\ChemDraw.msi`"" , `
                'REBOOT=ReallySuppress','/qb' -Wait

# 4. Activation Files
$activationDir = Join-Path $PSScriptRoot "Activation"

Start-Process -FilePath (Join-Path $activationDir 'Activate.exe') `
    -ArgumentList '23.0', 'IsInstaller', '/silent' `
    -Wait

#MSI Uninstall Code: msiexec /x "{8A0CD73D-AB37-4B90-98E8-3FDE4C765BB5}" /qn
