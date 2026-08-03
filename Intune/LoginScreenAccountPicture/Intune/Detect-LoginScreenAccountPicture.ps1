<#
.SYNOPSIS
    Detects the UMD Libraries default Windows account-picture deployment.

.DESCRIPTION
    Intune Win32 custom detection script. Detection succeeds only when the
    versioned registry sentinel is complete, the machine-wide policy is enabled,
    all seven account-picture files exist, and every file hash matches the hash
    recorded only after the install loop completed.

.PARAMETER ExpectedVersion
    Version expected in the registry sentinel. Keep this aligned with install.

.NOTES
    Author  : Oji McLeod, UMD Libraries
    Date    : 2026-08-01
    Version : 1.0.0
    Output remains well under Intune's 2,048-character recommendation.
    Exit 0 plus stdout: Detected
    Exit 1: Not detected
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedVersion = '1.0.0'
)

begin {
    $ErrorActionPreference = 'Stop'
    $pictureRoot = Join-Path -Path $env:ProgramData -ChildPath 'Microsoft\User Account Pictures'
    $policyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $sentinelPath = 'HKLM:\SOFTWARE\UMDLibraries\Intune\LoginScreenAccountPicture'
    $expectedNames = @('user.png', 'user.jpg', 'user.bmp', 'user-192.png', 'user-48.png', 'user-40.png', 'user-32.png')
}

process {
    try {
        if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) { exit 1 }
        if (-not (Test-Path -LiteralPath $sentinelPath)) { exit 1 }
        if (-not (Test-Path -LiteralPath $policyPath)) { exit 1 }

        $sentinel = Get-ItemProperty -LiteralPath $sentinelPath -ErrorAction Stop
        if ($sentinel.Version -ne $ExpectedVersion) { exit 1 }
        if ([int]$sentinel.InstallComplete -ne 1) { exit 1 }
        if ((Get-ItemPropertyValue -LiteralPath $policyPath -Name 'UseDefaultTile' -ErrorAction Stop) -ne 1) { exit 1 }

        $targetHashes = $sentinel.TargetHashesJson | ConvertFrom-Json -ErrorAction Stop
        foreach ($name in $expectedNames) {
            $targetPath = Join-Path -Path $pictureRoot -ChildPath $name
            if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) { exit 1 }

            $hashProperty = $targetHashes.PSObject.Properties[$name]
            if (-not $hashProperty) { exit 1 }

            $currentHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($currentHash -ne [string]$hashProperty.Value) { exit 1 }
        }

        Write-Output "UMD Libraries account picture $ExpectedVersion detected"
        exit 0
    }
    catch {
        exit 1
    }
}
