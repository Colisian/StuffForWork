$matlabInstallPath = "C:\Program Files\MATLAB\R2021a"  # Specify the installation path of Matlab
$matlabLicenseFile = "C:\Program Files\MATLAB\R2021a\licenses\license.dat" # Specify the path of the license file"

# Check if Matlab installation directoy exists
if (Test-Path -Path $matlabInstallPath) {
    <# Copy the license file to the Matlab installation directory #>
    Copy-Item -Path $matlabLicenseFile -Destination (Join-Path $matlabInstallPath "licenses") -Force

    #verify if the license file exists in the installtion directory
    $intatlledLicenseFile = Join-Path $matlabInstallPath "licenses\license.dat"
    if (Test-Path -Path $intatlledLicenseFile) {
        Write-Host "License file copied successfully"
    } else {
        Write-Host "License file not copied"
    }


    <# Create a shortcut to the Matlab executable #>
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$env:PUBLIC\Desktop\Matlab R2021a.lnk")
    $Shortcut.TargetPath = "$matlabInstallPath\bin\matlab.exe"
    $Shortcut.Save()


}
else {
    Write-Host "Matlab installation directory does not exist"}