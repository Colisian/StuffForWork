

#!!! THIS SCRIPT IS NOT WORKING !!!

$msiPath = "panoptorecorder.msi"

# Installation arguments put in an array
$msiArgs =  @("/i", $msiPath ,"/qn", "/l*v", "C:\PerfLogs\panoptoInstall.log", "PANOPTO_SERVER=umd.hosted.panopto.com")

# Start the installation process
$msiProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru

if ($msiProcess.ExitCode -eq 0) {
    <# Action to perform if the condition is true #>
    $RegFile = "panoptoregchanges.reg"

    # Import the registry changes
    reg import $RegFile /reg:64

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