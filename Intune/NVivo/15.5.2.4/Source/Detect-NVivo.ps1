[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'
$minimumVersion = [version]'15.5.2.4'
$sentinelPath = 'HKLM:\SOFTWARE\UMDLibraries\Intune\NVivo15'

function Get-NVivoRegistration {
    <#
    .SYNOPSIS
    Returns registered 64-bit and 32-bit NVivo installations.
    .NOTES
    Author: University of Maryland Libraries ITFO
    Date: 2026-09-02
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    Get-ItemProperty -Path $registryPaths |
        Where-Object {
            $_.DisplayName -match '^NVivo(?:\s+15)?$' -and
            $_.DisplayVersion
        } |
        Sort-Object PSPath -Unique
}

$sentinel = Get-ItemProperty -Path $sentinelPath
if (-not $sentinel -or $sentinel.PackageVersion -ne $minimumVersion.ToString()) {
    Write-Output 'NVivo package sentinel is missing or outdated.'
    exit 1
}

foreach ($entry in Get-NVivoRegistration) {
    try {
        $installedVersion = [version]$entry.DisplayVersion
        if ($installedVersion.Major -eq 15 -and $installedVersion -ge $minimumVersion) {
            Write-Output "Detected NVivo $installedVersion."
            exit 0
        }
    }
    catch {
        continue
    }
}

Write-Output "NVivo $minimumVersion or newer was not detected."
exit 1
