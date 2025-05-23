# Script to set Default Domain and restrict local logon

$domain = "umd.edu"
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$regName = "DefaultLogonDomain"
$regValue = $domain
$logFolder = "C:\Scripts"
$logFile = "$logFolder\SetDomain.txt"
# Ensure folder ex
if (-not (Test-Path $logFolder)){
    New-Item -Path $logFolder -ItemType Directory -Force
}
#Log exectuion details
$logEntry = "Script executed on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') "
Add-Content -Path $logFile -Value $logEntry
# Check if the registry path exists
if (-not (Test-Path $regPath)){
    New-Item -Path $regPath -Force
}

Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -Force



