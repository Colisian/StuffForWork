#define registry path
$regpath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

if (Test-Path $regpath) {
    # Check if registry key exists 
    $property = Get-ItemProperty -Path $regpath -Name "DisableLockWorkstation" -ErrorAction SilentlyContinue
    if ($property) {
        # Remove the DisableLockWorkstation
        Remove-ItemProperty -Path $regpath -Name "DisableLockWorkstation" -Force
        Write-Output "RemoveLock has been uninstalled successfully."
    } else {
        Write-Output "DisableLockWorkstation does not exist. RemoveLock is not installed"
    } 
} else {
    Write-Output "Registry path does not exist."
}