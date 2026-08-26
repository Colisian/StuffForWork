<#
.SYNOPSIS
    Detects the managed Pharos Remote installation for Microsoft Intune.

.DESCRIPTION
    Confirms the post-install sentinel, expected Database Service settings, and
    core Pharos Remote files. Exits 0 when compliant and 1 when not detected.

.NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-26
    Version: 1.0.0
    Intune detection output is intentionally kept under 2,048 characters.
#>
[CmdletBinding()]
param()

begin {
    $ErrorActionPreference = 'Stop'
    $expectedPackageVersion = '9.2.10000.194'
    $expectedInstallerSha256 = 'DCC4D481CA0135DB23C27F3E78D4CE67B3052F0FE35621CF08AE3D5D0769A656'
    $expectedDatabaseServer = 'LIBRDB407DV.ad.umd.edu'
    $expectedPort = '2355'
    $expectedTimeout = 120
}

process {
    $openedKeys = [System.Collections.Generic.List[IDisposable]]::new()
    try {
        $registry32 = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry32
        )
        $openedKeys.Add($registry32)

        $databaseKey = $registry32.OpenSubKey('SOFTWARE\Pharos\Database Server')
        if (-not $databaseKey) {
            throw 'Pharos Database Server registry key is missing.'
        }
        $openedKeys.Add($databaseKey)

        if ($databaseKey.GetValue('Host Address') -ne $expectedDatabaseServer) {
            throw 'Database Server host does not match.'
        }
        if ([string]$databaseKey.GetValue('Port Name') -ne $expectedPort) {
            throw 'Database Server port does not match.'
        }
        if ([int]$databaseKey.GetValue('Timeout') -ne $expectedTimeout) {
            throw 'Database Server timeout does not match.'
        }

        $sentinelKey = $null
        foreach ($registryView in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
            if ($sentinelKey) {
                break
            }
            if (-not [Environment]::Is64BitOperatingSystem -and $registryView -eq [Microsoft.Win32.RegistryView]::Registry64) {
                continue
            }

            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $registryView)
            $openedKeys.Add($baseKey)
            $candidateKey = $baseKey.OpenSubKey('SOFTWARE\UMD Libraries\Intune\Pharos Remote')
            if ($candidateKey) {
                $openedKeys.Add($candidateKey)
                $sentinelKey = $candidateKey
            }
        }

        if (-not $sentinelKey) {
            throw 'Managed-install sentinel is missing.'
        }
        if ($sentinelKey.GetValue('PackageVersion') -ne $expectedPackageVersion) {
            throw 'Managed package version does not match.'
        }
        if ($sentinelKey.GetValue('InstallerSha256') -ne $expectedInstallerSha256) {
            throw 'Managed installer hash does not match.'
        }

        $installPath = [string]$sentinelKey.GetValue('InstallPath')
        if ([string]::IsNullOrWhiteSpace($installPath)) {
            throw 'Managed install path is missing.'
        }
        if (-not (Test-Path -LiteralPath (Join-Path -Path $installPath -ChildPath 'AdminLauncher.exe') -PathType Leaf)) {
            throw 'AdminLauncher.exe is missing.'
        }
        if (-not (Test-Path -LiteralPath (Join-Path -Path $installPath -ChildPath 'Uninst.exe') -PathType Leaf)) {
            throw 'Uninst.exe is missing.'
        }

        Write-Output "Pharos Remote $expectedPackageVersion detected and configured."
        exit 0
    }
    catch {
        Write-Output "Pharos Remote not detected: $($_.Exception.Message)"
        exit 1
    }
    finally {
        foreach ($openedKey in $openedKeys) {
            if ($openedKey) {
                $openedKey.Dispose()
            }
        }
    }
}
