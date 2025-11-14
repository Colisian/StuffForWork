<#
.SYNOPSIS
    Detection script for Point and Print configuration.

.DESCRIPTION
    Detects whether Point and Print policies are properly configured for the trusted print server.
    Used by Intune to determine if the Point-and-Print.ps1 script needs to be deployed.
    Returns exit code 0 if configuration is present and correct, 1 if not.

.NOTES
    Expected Print Server: librps403v.ad.umd.edu
    Designed for Intune Win32 app detection
#>

$expectedServer = 'librps403v.ad.umd.edu'
$ppRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'
$pkgRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PackagePointAndPrint'

try {
    # Check if Point and Print registry key exists
    if (-not (Test-Path $ppRoot)) {
        Write-Host "NOT CONFIGURED: Point and Print registry key does not exist"
        exit 1
    }

    # Check if Package Point and Print registry key exists
    if (-not (Test-Path $pkgRoot)) {
        Write-Host "NOT CONFIGURED: Package Point and Print registry key does not exist"
        exit 1
    }

    # Get Point and Print settings
    $ppSettings = Get-ItemProperty -Path $ppRoot -ErrorAction Stop

    # Verify critical settings
    $checks = @{
        'Restricted' = 1
        'TrustedServers' = 1
        'NoWarningNoElevationOnInstall' = 1
        'UpdatePromptSettings' = 2
        'RestrictDriverInstallationToAdministrators' = 0
    }

    $allChecksPass = $true
    foreach ($setting in $checks.GetEnumerator()) {
        $actualValue = $ppSettings.($setting.Key)
        if ($actualValue -ne $setting.Value) {
            Write-Host "MISMATCH: $($setting.Key) = $actualValue (expected $($setting.Value))"
            $allChecksPass = $false
        }
    }

    # Check ServerList contains expected server (case-insensitive)
    $serverList = $ppSettings.ServerList
    if ($serverList -notmatch [regex]::Escape($expectedServer)) {
        Write-Host "MISMATCH: ServerList does not contain '$expectedServer' (current: $serverList)"
        $allChecksPass = $false
    }

    # Check Package Point and Print settings
    $pkgSettings = Get-ItemProperty -Path $pkgRoot -ErrorAction Stop

    if ($pkgSettings.TrustedServers -ne 1) {
        Write-Host "MISMATCH: Package Point and Print TrustedServers = $($pkgSettings.TrustedServers) (expected 1)"
        $allChecksPass = $false
    }

    if ($pkgSettings.ServerList -notmatch [regex]::Escape($expectedServer)) {
        Write-Host "MISMATCH: Package Point and Print ServerList does not contain '$expectedServer'"
        $allChecksPass = $false
    }

    if ($allChecksPass) {
        Write-Host "SUCCESS: Point and Print is properly configured for $expectedServer"
        exit 0
    } else {
        Write-Host "INCOMPLETE: Point and Print configuration needs to be updated"
        exit 1
    }

} catch {
    Write-Host "ERROR: Failed to detect Point and Print configuration: $($_.Exception.Message)"
    exit 1
}
