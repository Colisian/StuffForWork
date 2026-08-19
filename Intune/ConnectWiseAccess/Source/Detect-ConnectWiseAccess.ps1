<#
.SYNOPSIS
    Intune Win32 custom detection script for the UMD Libraries ConnectWise Access agent.

.DESCRIPTION
    Reports the app as installed when the stable instance-specific Windows service exists
    and the registered ScreenConnect MSI version is 26.4.3.9662 or newer. A minimum-version
    comparison upgrades older agents while allowing future ConnectWise self-updates to
    remain compliant even when their MSI product code changes.

    Intune Win32 custom detection contract:
        detected     = exit code 0 AND at least one line on STDOUT
        not detected = exit code 0 AND empty STDOUT

    Configure Run script as 32-bit process on 64-bit clients to No.

.NOTES
    Author  : Oji McLeod - ITFO / Digital Services & Technologies, UMD Libraries
    Date    : 2026-08-18
    Version : 1.0.0
    Stdout  : kept well under Intune's 2048-character limit
#>
[CmdletBinding()]
param()

function Get-ConnectWiseAccessProduct {
    <#
    .SYNOPSIS
        Gets registered products for the UMD Libraries ConnectWise Access agent.

    .PARAMETER DisplayName
        Exact Add/Remove Programs display name to locate.

    .NOTES
        Author  : Oji McLeod - ITFO / Digital Services & Technologies, UMD Libraries
        Date    : 2026-08-18
        Version : 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    begin {
        $ErrorActionPreference = 'Stop'
        $uninstallRoots = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )
    }

    process {
        foreach ($uninstallRoot in $uninstallRoots) {
            if (-not (Test-Path -LiteralPath $uninstallRoot)) { continue }

            Get-ChildItem -LiteralPath $uninstallRoot -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $product = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                    if ($product.DisplayName -eq $DisplayName) {
                        $product
                    }
                }
        }
    }
}

$ErrorActionPreference = 'SilentlyContinue'

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    # Empty stdout and exit 0 means not detected.
    exit 0
}

$expectedDisplayName = 'ScreenConnect Client (f81fbe41367f771e)'
$expectedServiceName = 'ScreenConnect Client (f81fbe41367f771e)'
$minimumVersion = [version]'26.4.3.9662'

try {
    $installedService = Get-Service -Name $expectedServiceName -ErrorAction Stop
    $registeredProducts = @(Get-ConnectWiseAccessProduct -DisplayName $expectedDisplayName)

    $installedVersions = @(
        $registeredProducts | ForEach-Object {
            try { [version]$_.DisplayVersion } catch { $null }
        }
    )
    $currentVersion = $installedVersions | Sort-Object -Descending | Select-Object -First 1

    if ($installedService -and $currentVersion -and $currentVersion -ge $minimumVersion) {
        Write-Output "Detected: ConnectWise Access $currentVersion"
    }
}
catch {
    # Empty stdout and exit 0 means not detected.
}

exit 0
