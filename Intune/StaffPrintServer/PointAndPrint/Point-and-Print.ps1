<#
.SYNOPSIS
    Configures Point and Print settings for print servers in an Intune-managed environment.

.DESCRIPTION
    Sets machine-level Point and Print policies to allow non-admin users to install
    printer drivers from trusted print servers without elevation prompts.
    Designed for deployment via Intune Win32 app in System context.

.NOTES
    Install Command (Intune):
    powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File .\Point-and-Print.ps1

    Detection Script:
    Use Point-and-Print-Detection.ps1
#>

$Servers = @('librps403v.ad.umd.edu')

$serverList = ($Servers | ForEach-Object { $_.ToLower().Trim('\') } | Where-Object { $_ }) -join ';'

# Registry paths
$ppRoot   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'
$pkgRoot  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PackagePointAndPrint'

# Create keys if missing
New-Item -Path $ppRoot  -Force | Out-Null
New-Item -Path $pkgRoot -Force | Out-Null

# ---- Point and Print Restrictions (Device) ----
# Users can only point and print to these servers
Set-ItemProperty -Path $ppRoot -Name 'Restricted' -Type DWord -Value 1
Set-ItemProperty -Path $ppRoot -Name 'TrustedServers' -Type DWord -Value 1
Set-ItemProperty -Path $ppRoot -Name 'ServerList' -Type String -Value $serverList

# Security prompts
# NoWarningNoElevationOnInstall: 1 = do not show warning/elevation on new installs
# UpdatePromptSettings: 2 = do not show warning/elevation on updates
Set-ItemProperty -Path $ppRoot -Name 'NoWarningNoElevationOnInstall' -Type DWord -Value 1
Set-ItemProperty -Path $ppRoot -Name 'UpdatePromptSettings' -Type DWord -Value 2

# Newer hardening toggle (introduced with PrintNightmare mitigations)
# 0 = allow non-admins to install drivers from trusted servers
Set-ItemProperty -Path $ppRoot -Name 'RestrictDriverInstallationToAdministrators' -Type DWord -Value 0

# ---- Package Point and Print – Approved servers (Device) ----
# Restricts package PnP to approved servers and lists them
Set-ItemProperty -Path $pkgRoot -Name 'TrustedServers' -Type DWord -Value 1
Set-ItemProperty -Path $pkgRoot -Name 'ServerList' -Type String -Value $serverList

Write-Host "Point and Print policies configured successfully."

# Restart spooler so settings take effect immediately
Write-Host "Restarting Print Spooler service..."
Restart-Service -Name Spooler -Force

# Show effective values
Write-Host "`nConfigured trusted servers: $serverList"
Get-ItemProperty -Path $ppRoot  | Select-Object Restricted,TrustedServers,ServerList,NoWarningNoElevationOnInstall,UpdatePromptSettings,RestrictDriverInstallationToAdministrators
Get-ItemProperty -Path $pkgRoot | Select-Object TrustedServers,ServerList
Write-Host "`nPoint and Print configuration completed successfully."
exit 0