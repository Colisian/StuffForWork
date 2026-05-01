<#
.SYNOPSIS
    Intune Win32 detection rule for the Arial Unicode MS font deployment.

.DESCRIPTION
    Verifies that every font in the manifest is present in %WINDIR%\Fonts AND
    has a matching value under
    HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts.

    Intune detection contract:
        - Detected     : write to STDOUT and exit 0
        - Not detected : no STDOUT and exit 0 (or non-zero)

.NOTES
    Author : Oji McLeod (cmcleod1@umd.edu)
    Date   : 2026-05-01
    Version: 1.0.0
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$fontManifest = @(
    @{ File = 'arial unicode ms.otf';      RegName = 'Arial Unicode MS (OpenType)' }
    @{ File = 'arial unicode ms bold.otf'; RegName = 'Arial Unicode MS Bold (OpenType)' }
)

$fontsDir     = Join-Path $env:windir 'Fonts'
$registryPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'

try {
    foreach ($entry in $fontManifest) {
        $fontPath = Join-Path $fontsDir $entry.File
        if (-not (Test-Path -Path $fontPath -PathType Leaf)) { exit 0 }

        $value = (Get-ItemProperty -Path $registryPath -Name $entry.RegName -ErrorAction SilentlyContinue).$($entry.RegName)
        if ([string]::IsNullOrEmpty($value)) { exit 0 }
        if ($value -ine $entry.File) { exit 0 }
    }
    Write-Output 'Arial Unicode MS fonts detected.'
    exit 0
} catch {
    # Any unexpected failure: report not-detected so Intune re-runs install.
    exit 0
}
