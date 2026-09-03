[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$keyPath = Join-Path $scriptDir 'NVivoLicense.key'
$profilePath = Join-Path $scriptDir 'Activation.xml'
$logRoot = 'C:\ProgramData\UMDLibraries\NVivo'
$logPath = Join-Path $logRoot 'Activate-NVivo.log'
$sentinelPath = 'HKLM:\SOFTWARE\UMDLibraries\Intune\NVivo15Activation'
$packageVersion = '1.0.0'
$licenseKey = $null

function Get-NVivoExecutable {
    <#
    .SYNOPSIS
    Finds the installed NVivo 15 executable.
    .NOTES
    Author: University of Maryland Libraries ITFO
    Date: 2026-09-03
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    $defaultPath = Join-Path $env:ProgramFiles 'QSR\NVivo 15\NVivo.exe'
    if (Test-Path -LiteralPath $defaultPath -PathType Leaf) {
        return $defaultPath
    }

    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $registration = Get-ItemProperty -Path $registryPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '^NVivo(?:\s+15)?$' } |
        Select-Object -First 1

    if ($registration.InstallLocation) {
        $registeredPath = Join-Path $registration.InstallLocation 'NVivo.exe'
        if (Test-Path -LiteralPath $registeredPath -PathType Leaf) {
            return $registeredPath
        }
    }

    throw 'NVivo 15 is not installed or NVivo.exe could not be located.'
}

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
Add-Content -LiteralPath $logPath -Value "[$([DateTime]::Now.ToString('s'))] Activation started."

try {
    if (-not (Test-Path -LiteralPath $keyPath -PathType Leaf)) {
        throw 'The transient NVivo license file is missing.'
    }
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
        throw 'Activation.xml is missing.'
    }

    $licenseKey = [IO.File]::ReadAllText($keyPath).Trim()
    if ($licenseKey -notmatch '^[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}$') {
        throw 'The NVivo license key does not match the expected format.'
    }

    [xml]$activationProfile = Get-Content -LiteralPath $profilePath -Raw
    if (-not $activationProfile.Activation.Request.Email) {
        throw 'Activation.xml does not contain the required activation profile.'
    }

    $keyBytes = [Text.Encoding]::UTF8.GetBytes($licenseKey)
    $keyFingerprint = [BitConverter]::ToString(
        [Security.Cryptography.SHA256]::Create().ComputeHash($keyBytes)
    ).Replace('-', '')

    $existing = Get-ItemProperty -Path $sentinelPath -ErrorAction SilentlyContinue
    if ($existing.PackageVersion -eq $packageVersion -and
        $existing.KeyFingerprint -eq $keyFingerprint) {
        Add-Content -LiteralPath $logPath -Value "[$([DateTime]::Now.ToString('s'))] Matching activation already completed."
        exit 0
    }

    $nvivoPath = Get-NVivoExecutable
    if (-not $PSCmdlet.ShouldProcess($nvivoPath, 'Activate NVivo 15 silently')) {
        exit 0
    }

    # The key is required by the vendor CLI. Never log $arguments or the process command line.
    $arguments = @('-i', $licenseKey, '-a', "`"$profilePath`"", '-skr')
    $process = Start-Process -FilePath $nvivoPath -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "NVivo activation returned exit code $($process.ExitCode)."
    }

    if ($PSCmdlet.ShouldProcess($sentinelPath, 'Write activation completion sentinel')) {
        New-Item -Path $sentinelPath -Force | Out-Null
        New-ItemProperty -Path $sentinelPath -Name 'PackageVersion' -Value $packageVersion -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $sentinelPath -Name 'KeyFingerprint' -Value $keyFingerprint -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $sentinelPath -Name 'ActivatedUtc' -Value ([DateTime]::UtcNow.ToString('o')) -PropertyType String -Force | Out-Null
    }

    Add-Content -LiteralPath $logPath -Value "[$([DateTime]::Now.ToString('s'))] Activation completed successfully."
    exit 0
}
catch {
    Add-Content -LiteralPath $logPath -Value "[$([DateTime]::Now.ToString('s'))] ERROR: $($_.Exception.Message)"
    Write-Error $_
    exit 1
}
finally {
    $licenseKey = $null
    if (Test-Path -LiteralPath $keyPath -PathType Leaf) {
        if ($PSCmdlet.ShouldProcess($keyPath, 'Delete transient license file')) {
            Remove-Item -LiteralPath $keyPath -Force -ErrorAction SilentlyContinue
        }
    }
}
