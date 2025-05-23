# Define variables
$installerPath = "C:\CrowdStrike\Windows\FalconSensor_Windows 7.20.exe"
$customerID = ""  # Replace with your actual Customer ID

# Check if the installer exists
if (Test-Path $installerPath) {
    Write-Host "CrowdStrike installer found at $installerPath."

    # Construct the installation command
    $installCommand = "$installerPath /install /passive CID=$customerID"

    # Execute the installation commands
    try {
        Start-Process -FilePath $installerPath -ArgumentList "/install", "/passive", "CID=$customerID" -Wait -NoNewWindow
        Write-Host "CrowdStrike Falcon installation completed successfully."
    } catch {
        Write-Error "An error occurred during the installation process: $_"
    }
} else {
    Write-Error "CrowdStrike installer not found at $installerPath. Please ensure the file exists."
}