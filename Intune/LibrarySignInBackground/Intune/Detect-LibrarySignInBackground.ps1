<#
.SYNOPSIS
    Detects the UMD Libraries sign-in background deployment.

.DESCRIPTION
    Intune Win32 custom detection script. It verifies the completion sentinel,
    expected version, generated image hash, and the current LockScreenImage
    policy. Output is intentionally short for Intune reporting.

.NOTES
    Author  : Oji McLeod, UMD Libraries
    Date    : 2026-08-29
    Version : 1.0.1
#>
#Requires -Version 5.1
[CmdletBinding()]
param([string]$ExpectedVersion = '1.0.1')

begin {
    $ErrorActionPreference = 'Stop'
    $sentinelPath = 'HKLM:\SOFTWARE\UMDLibraries\Intune\LibrarySignInBackground'
    $personalizationPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
    $systemPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
}

process {
    try {
        if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) { exit 1 }
        if (-not (Test-Path -LiteralPath $sentinelPath) -or -not (Test-Path -LiteralPath $personalizationPath)) { exit 1 }
        if ((Test-Path -LiteralPath $systemPolicyPath) -and
            ((Get-ItemProperty -LiteralPath $systemPolicyPath).DisableLogonBackgroundImage -eq 1)) { exit 1 }
        $sentinel = Get-ItemProperty -LiteralPath $sentinelPath
        if ($sentinel.Version -ne $ExpectedVersion -or [int]$sentinel.InstallComplete -ne 1) { exit 1 }
        if (-not (Test-Path -LiteralPath $sentinel.ImagePath -PathType Leaf)) { exit 1 }
        if ((Get-ItemPropertyValue -LiteralPath $personalizationPath -Name 'LockScreenImage') -ne $sentinel.ImagePath) { exit 1 }
        if ((Get-FileHash -LiteralPath $sentinel.ImagePath -Algorithm SHA256).Hash -ne $sentinel.ImageHash) { exit 1 }
        Write-Output "UMD Libraries sign-in background $ExpectedVersion detected"
        exit 0
    }
    catch { exit 1 }
}
