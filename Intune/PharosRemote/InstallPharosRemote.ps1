# Ensure registry path exists
$regPath = "HKLM:\SOFTWARE\Pharos\Database Server"
if (-not (Test-Path $regPath)) {
  New-Item -Path $regPath -Force | Out-Null
}

# Set values
Set-ItemProperty -Path $regPath -Name "Host Address" -Value "LIBRDB407DV.ad.umd.edu" -Force
Set-ItemProperty -Path $regPath -Name "Port Name" -Value "2355" -Force
Set-ItemProperty -Path $regPath -Name "Timeout" -Value 120 -Type DWord -Force

# Run installer
Start-Process -FilePath ".\RemoteInstaller.exe" -ArgumentList "/q" -Wait
