[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
$targetVersion = [version]'15.5.2.4'
$expectedHash = '32A2B6A7E2F448AA96819462E47F2090EE9000D6457A132BE7B5773DD9674DD7'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$installerPath = Join-Path $scriptDir 'NVivo.x64.exe'
$logRoot = 'C:\ProgramData\UMDLibraries\NVivo'
$wrapperLog = Join-Path $logRoot 'Install-NVivo.log'
$msiLog = Join-Path $logRoot 'Install-NVivo-MSI.log'
$sentinelPath = 'HKLM:\SOFTWARE\UMDLibraries\Intune\NVivo15'

function Get-NVivoRegistration {
    <#
    .SYNOPSIS
    Returns registered 64-bit and 32-bit NVivo 15 installations.
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

    Get-ItemProperty -Path $registryPaths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -match '^NVivo(?:\s+15)?$' -and
            $_.DisplayVersion
        } |
        Sort-Object PSPath -Unique
}

function Test-NVivoInstalled {
    <#
    .SYNOPSIS
    Tests whether the target or a newer NVivo 15 build is registered.
    .NOTES
    Author: University of Maryland Libraries ITFO
    Date: 2026-09-02
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [version]$MinimumVersion
    )

    foreach ($entry in Get-NVivoRegistration) {
        try {
            $installedVersion = [version]$entry.DisplayVersion
            if ($installedVersion.Major -eq 15 -and $installedVersion -ge $MinimumVersion) {
                return $true
            }
        }
        catch {
            Write-Warning "Ignoring invalid NVivo version '$($entry.DisplayVersion)'."
        }
    }

    return $false
}

function Set-NVivoSentinel {
    <#
    .SYNOPSIS
    Writes the Intune package completion sentinel.
    .NOTES
    Author: University of Maryland Libraries ITFO
    Date: 2026-09-02
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [int]$InstallerExitCode
    )

    if ($PSCmdlet.ShouldProcess($sentinelPath, 'Write NVivo Intune detection sentinel')) {
        New-Item -Path $sentinelPath -Force | Out-Null
        New-ItemProperty -Path $sentinelPath -Name 'PackageVersion' -Value $targetVersion.ToString() -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $sentinelPath -Name 'SourceSHA256' -Value $expectedHash -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $sentinelPath -Name 'InstallerExitCode' -Value $InstallerExitCode -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $sentinelPath -Name 'LastInstallUtc' -Value ([DateTime]::UtcNow.ToString('o')) -PropertyType String -Force | Out-Null
    }
}

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
Start-Transcript -Path $wrapperLog -Append | Out-Null

try {
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        throw "Installer not found: $installerPath"
    }

    $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
        throw "Installer SHA256 mismatch. Expected $expectedHash; received $actualHash."
    }

    if (Test-NVivoInstalled -MinimumVersion $targetVersion) {
        Write-Output "NVivo $targetVersion or newer is already installed."
        Set-NVivoSentinel -InstallerExitCode 0
        exit 0
    }

    if (-not $PSCmdlet.ShouldProcess($installerPath, "Install NVivo $targetVersion silently")) {
        exit 0
    }

    $arguments = @('/S', "/v`"/qn REBOOT=ReallySuppress /L*v $msiLog`"")
    $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -PassThru
    $validExitCodes = @(0, 1641, 3010)
    if ($process.ExitCode -notin $validExitCodes) {
        throw "NVivo installer returned exit code $($process.ExitCode)."
    }

    if (-not (Test-NVivoInstalled -MinimumVersion $targetVersion)) {
        throw 'Installer reported success, but the expected NVivo registration was not found.'
    }

    Set-NVivoSentinel -InstallerExitCode $process.ExitCode
    Write-Output "NVivo $targetVersion installation completed with exit code $($process.ExitCode)."
    exit $process.ExitCode
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
