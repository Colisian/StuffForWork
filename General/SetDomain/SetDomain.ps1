# Script to set Default Domain and restrict local logon

$domain = "umd.edu"
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$regName = "DefaultLogonDomain"
$regValue = $domain

if (-not (Test-Path $regPath)){
    New-Item -Path $regPath -Force
}

Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -Force
Set-ItemProperty -Path $regPath -Name "DontDisplayLastUserName" -Value 1 -Force
