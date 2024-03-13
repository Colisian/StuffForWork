
#run the following command to install the Panopto Recorder
# powershell.exe -executionpolicy bypass -file .\installpanopto.ps1 
# to run the script
# INstallation command for Panopto Recorder MSI

$msiPath = "panoptorecorder.msi"

# Installation arguments put in an array
$msiArgs =  @("/i", $msiPath ,"/qn", "/l*v", "C:\PerfLogs\panoptoInstall.log", "PANOPTO_SERVER=umd.hosted.panopto.com")

# Start the installation process
$msiProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru

if ($msiProcess.ExitCode -eq 0) {
    <# Action to perform if the condition is true #>
    $RegFile = ".\panoptoregchanges.reg"

     # Determine the correct cmd path for 64-bit execution
     $cmdPath = if ([Environment]::Is64BitOperatingSystem) { "$env:windir\Sysnative\cmd.exe" } else { "cmd.exe" }
    
     # Import the registry changes using the determined cmd path for 64-bit context
     Start-Process -FilePath $cmdPath -ArgumentList "/c reg import `"$RegFile`"" -Wait

    # Check if the registry changes were imported successfully
    if ($LASTEXITCODE -eq 0) {
        <# Action to perform if the condition is true #>
        Write-Host "Registry changes imported successfully"
    } else {
        Write-Host "Failed to import registry changes"
    }
} else {
    <# Action to perform if the condition is false #>
    Write-Error "Failed to install Panopto Recorder. Exit code: $($msiProcess.ExitCode)"
}