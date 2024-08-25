$logFolder = "C:\Scripts"
$logFile = "$logFolder\ScriptExecutionLog.txt"
$gpRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{25CA8579-1BD8-469c-B9FC-6AC45A161C18}\"
$regName = "Disabled"
$regValue = 1

# Ensure the Scripts folder exists
if (-not (Test-Path $logFolder)){
    New-Item -Path $logFolder -ItemType Directory -Force
}

# Log the execution details
$logEntry = " GlobalProtect Script executed on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') "
Add-Content -Path $logFile -Value $logEntry

#Disable GlobalProtect VPN as Sign-in option
try {
    Set-ItemProperty -Path $gpRegPath -Name $regName -Value $regValue -ErrorAction Stop
    # If the command succeeds, log the result
    Add-Content -Path $logFile -Value "GlobalProtect sign-in option disabled." 
} catch {
    # If the command fails, log the failure
    Add-Content -Path $logFile -Value "Failed to disable GlobalProtect sign-in option."
}