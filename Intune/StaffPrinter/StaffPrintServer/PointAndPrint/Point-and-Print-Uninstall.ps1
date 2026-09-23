<#
.SYNOPSIS
    Removes Point and Print settings configured by the install script.

.DESCRIPTION
    Removes machine-level Point and Print policies that were set to allow
    non-admin users to install printer drivers from trusted print servers.
    Designed for deployment via Intune Win32 app uninstall command in System context.

.NOTES
    Uninstall Command (Intune):
    powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File .\Point-and-Print-Uninstall.ps1
#>

# Registry paths
$ppRoot   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'
$pkgRoot  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PackagePointAndPrint'

Write-Host "Removing Point and Print policies..."

# Remove Point and Print Restrictions settings
if (Test-Path $ppRoot) {
    Write-Host "Removing Point and Print registry values..."

    # Remove individual values (safer than removing entire key)
    $valuesToRemove = @(
        'Restricted',
        'TrustedServers',
        'ServerList',
        'NoWarningNoElevationOnInstall',
        'UpdatePromptSettings',
        'RestrictDriverInstallationToAdministrators'
    )

    foreach ($value in $valuesToRemove) {
        if (Get-ItemProperty -Path $ppRoot -Name $value -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path $ppRoot -Name $value -Force -ErrorAction SilentlyContinue
            Write-Host "  Removed: $value"
        }
    }

    # Remove the key if it's now empty
    $remainingValues = Get-ItemProperty -Path $ppRoot -ErrorAction SilentlyContinue
    if ($remainingValues.PSObject.Properties.Name.Count -le 3) {  # Only PSPath, PSParentPath, PSChildName remain
        Remove-Item -Path $ppRoot -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed empty registry key: PointAndPrint"
    }
}

# Remove Package Point and Print settings
if (Test-Path $pkgRoot) {
    Write-Host "Removing Package Point and Print registry values..."

    $pkgValuesToRemove = @(
        'TrustedServers',
        'ServerList'
    )

    foreach ($value in $pkgValuesToRemove) {
        if (Get-ItemProperty -Path $pkgRoot -Name $value -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path $pkgRoot -Name $value -Force -ErrorAction SilentlyContinue
            Write-Host "  Removed: $value"
        }
    }

    # Remove the key if it's now empty
    $remainingValues = Get-ItemProperty -Path $pkgRoot -ErrorAction SilentlyContinue
    if ($remainingValues.PSObject.Properties.Name.Count -le 3) {
        Remove-Item -Path $pkgRoot -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed empty registry key: PackagePointAndPrint"
    }
}

# Restart spooler so settings take effect immediately
Write-Host "`nRestarting Print Spooler service..."
Restart-Service -Name Spooler -Force

Write-Host "`nPoint and Print policies removed successfully."
exit 0
