$matlabInstallPath = "C:\Program Files\MATLAB\R2019b" #Specify install path
$licenseFilePath = "$env:USERPROFILE\Downloads\license.dat" #Specify license file path

#Check if the license file exists
if (Test-Path -Path $licenseFilePath) {
    if(Test-Path -Path $matlabInstallPath){
        #Check if Matlab installtion directory exists
        if (Test-Path - Path $matlabInstallPath) {
            #Copy the license file to the Matlab installation directory
            Copy-Item -Path $licenseFilePath -Destination (Join-Path $matlabInstallPath "licenses") -Force

            #Verify if the license file exists in the installation directory
            $installedLicenseFile = Join-Path $matlabInstallPath "licenses\license.dat"
            if (Test-Path -Path $installedLicenseFile) {
                Write-Host "License file copied successfully"
            } else {
                Write-Host "License file not copied"
            }

            #Create a shortcut to the Matlab executable
            $WshShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WshShell.CreateShortcut("$env:PUBLIC\Desktop\Matlab R2019b.lnk")
            $Shortcut.TargetPath = "$matlabInstallPath\bin\matlab.exe"
            $Shortcut.Save()
        }
        else {
            Write-Host "Matlab installation directory does not exist"
        }
    }
}
else {
    Write-Host "License file does not exist"
}
```