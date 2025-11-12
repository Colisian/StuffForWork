<#
.SYNOPSIS
    Configures Point and Print settings for print servers in an Intune-managed environment.
#>

$Servers = @('librps403v.ad.umd.edu')

# Must run as admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Run this script in an elevated PowerShell session."
    exit 1
}

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
Set-ItemProperty -Path $ppRoot -Name 'UpdatePromptSettings'           -Type DWord -Value 2

# Newer hardening toggle (introduced with PrintNightmare mitigations)
# 0 = allow non-admins to install drivers from trusted servers
Set-ItemProperty -Path $ppRoot -Name 'RestrictDriverInstallationToAdministrators' -Type DWord -Value 0

# ---- Package Point and Print – Approved servers (Device) ----
# Restricts package PnP to approved servers and lists them
Set-ItemProperty -Path $pkgRoot -Name 'TrustedServers' -Type DWord -Value 1
Set-ItemProperty -Path $pkgRoot -Name 'ServerList'     -Type String -Value $serverList

# ---- OPTIONAL: Neutralize stricter user-scope override for current user ----
# Comment out the next block if you don't want to touch HKCU
$ppUser = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'
if (Test-Path $ppUser) {
    try {
        Remove-Item $ppUser -Recurse -Force -ErrorAction Stop
        Write-Host "Removed user-scope PointAndPrint policy override (HKCU)."
    } catch {
        Write-Warning "Could not remove HKCU PointAndPrint key: $($_.Exception.Message)"
    }
}

# Restart spooler so settings take effect immediately
Restart-Service -Name Spooler -Force

# Show effective values
Write-Host "`nConfigured trusted servers: $serverList"
Get-ItemProperty -Path $ppRoot  | Select-Object Restricted,TrustedServers,ServerList,NoWarningNoElevationOnInstall,UpdatePromptSettings,RestrictDriverInstallationToAdministrators
Get-ItemProperty -Path $pkgRoot | Select-Object TrustedServers,ServerList
Write-Host "`nDone."