<#
.SYNOPSIS
    Intune Win32 custom detection script for the LibGuest session broker.

.DESCRIPTION
    Uploaded to Intune separately from the .intunewin package; it is not bundled.

    Detection keys on a registry sentinel rather than a file or folder rule. Most
    of what this app does is not a file: Default user hive policy, machine-wide
    Edge policy, an ACL, and a Startup shortcut. A file rule would report the app
    as installed whenever the files copied, even if every configuration step
    afterwards failed. The install script writes the sentinel last, so it exists
    only when the whole run succeeded.

    The corroborating checks below guard the case where something removes part of
    the configuration without removing the sentinel. Any of them failing means
    "not installed", and Intune reinstalls.

    Intune contract:
      exit 0 with output on STDOUT -> detected
      exit 0 with no output        -> not detected
      nonzero exit                 -> not detected

.NOTES
    Author:  Oji / UMD Libraries
    Date:    2026-07-27
    Version: 0.3.0

    Keep ExpectedVersion in step with $productVersion in
    Install-LibGuestSessionBroker.ps1. They are separate constants because a
    detection script runs standalone and cannot read the package. Bumping one
    without the other makes every device report as not installed, which triggers a
    fleet-wide reinstall.

    In Intune, set "Run script as 32-bit process on 64-bit clients" to NO, or the
    sentinel is read from WOW6432Node and never found.

    Keep STDOUT short; Intune truncates it.
#>

[CmdletBinding()]
param()

begin {
    $ErrorActionPreference = 'Stop'
}

end {
    $expectedVersion = '0.3.1'
    $sentinelSubKey = 'SOFTWARE\UMDLibraries\LibGuestSessionBroker'

    try {
        # Explicitly the 64-bit view. Belt and braces alongside the Intune setting
        # below: if this ever runs 32-bit, HKLM\SOFTWARE is redirected and the
        # sentinel would never be found, so every device would reinstall forever.
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
        try {
            $sentinel = $baseKey.OpenSubKey($sentinelSubKey)
            if ($null -eq $sentinel) {
                exit 0  # No output: not detected.
            }
            try {
                $installedVersion = $sentinel.GetValue('Version')
                $installPath = $sentinel.GetValue('InstallPath')
            }
            finally { $sentinel.Dispose() }
        }
        finally { $baseKey.Dispose() }

        if ($installedVersion -ne $expectedVersion) {
            exit 0
        }

        $installRoot = if ($installPath) { $installPath } else { 'C:\ProgramData\LibGuestSessionBroker' }

        $brokerScript = Join-Path $installRoot 'Prototype\Start-LibGuestSessionBroker.ps1'
        if (-not (Test-Path -LiteralPath $brokerScript -PathType Leaf)) {
            exit 0
        }

        $startupShortcut = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp\UMD Libraries Guest Access.lnk'
        if (-not (Test-Path -LiteralPath $startupShortcut -PathType Leaf)) {
            exit 0
        }

        Write-Output "LibGuestSessionBroker $expectedVersion detected"
        exit 0
    }
    catch {
        # Never report detected on an error path: a transient failure that printed
        # to STDOUT would leave a broken install in place.
        exit 1
    }
}
