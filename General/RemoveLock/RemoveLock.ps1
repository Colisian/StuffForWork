#Define registry path
$regpath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

#Create registry if path does not exist

if (-not (Test-Path $regpath)) {
    New-Item -Path $regpath -Force
}

#Set the disable lock screen value to diasble Lock workstation
New-ItemProperty -Path $regpath -Name "DisableLockWorkstation" -Value 1 -PropertyType DWORD -Force