#requires -Version 5.1
<#
.SYNOPSIS
    Intune custom detection script for Install-DellBIOSConfig.ps1.

.DESCRIPTION
    Returns exit code 0 and writes output only when the marker and all requested
    BIOS values are compliant. It never needs or reads the BIOS password.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ConfigVersion = '1.0.0'
$LogRoot = Join-Path $env:ProgramData 'Dell\BIOSConfig'
$LogFile = Join-Path $LogRoot 'Detect-DellBIOSConfig.log'
$RegistryPath = 'HKLM:\SOFTWARE\StuffForWork\DellBIOSConfig'

function Write-Log {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    if (-not (Test-Path -LiteralPath $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff K'), $Level, $Message
    [System.IO.File]::AppendAllText($LogFile, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
}

function Get-CctkPath {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Dell\Command Configure\X86_64\cctk.exe'),
        (Join-Path $env:ProgramFiles 'Dell\Command Configure\X86_64\cctk.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Dell\Command Configure\cctk.exe'),
        (Join-Path $env:ProgramFiles 'Dell\Command Configure\cctk.exe')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    throw 'cctk.exe was not found.'
}

function Get-CctkSetting {
    param([Parameter(Mandatory)][string]$Cctk, [Parameter(Mandatory)][string]$Option, [Parameter(Mandatory)][string]$OutputName)
    $output = @(& $Cctk "--$Option" 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "CCTK could not read $OutputName (exit code $LASTEXITCODE)." }
    $pattern = '^(?i:{0})\s*=\s*(.+?)\s*$' -f [regex]::Escape($OutputName)
    $match = $output | ForEach-Object { [regex]::Match([string]$_, $pattern) } | Where-Object { $_.Success } | Select-Object -Last 1
    if ($null -eq $match) { throw "CCTK did not return $OutputName." }
    return $match.Groups[1].Value.Trim()
}

try {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($computerSystem.Manufacturer -notmatch '(?i)dell') { throw 'Non-Dell hardware.' }

    $marker = Get-ItemProperty -Path $RegistryPath -ErrorAction Stop
    if ($marker.Version -ne $ConfigVersion -or $marker.State -ne 'Compliant') {
        throw 'Deployment marker is missing, outdated, or not compliant.'
    }

    $cctk = Get-CctkPath
    $desiredSettings = @(
        [pscustomobject]@{ OutputName = 'WakeOnLan';  CctkOption = 'WakeonLAN'; DesiredValue = 'LanOnly' },
        [pscustomobject]@{ OutputName = 'AcPwrRcvry'; CctkOption = 'AcPwrRcvry'; DesiredValue = 'Last' },
        [pscustomobject]@{ OutputName = 'AutoOn';     CctkOption = 'AutoOn';     DesiredValue = 'Everyday' },
        [pscustomobject]@{ OutputName = 'AutoOnHr';   CctkOption = 'AutoOnHr';   DesiredValue = '6' },
        [pscustomobject]@{ OutputName = 'AutoOnMn';   CctkOption = 'AutoOnMn';   DesiredValue = '0' }
    )

    foreach ($setting in $desiredSettings) {
        $value = Get-CctkSetting -Cctk $cctk -Option $setting.CctkOption -OutputName $setting.OutputName
        if ($value -ine $setting.DesiredValue) {
            throw "$($setting.OutputName) is '$value', not '$($setting.DesiredValue)'."
        }
    }

    Write-Log "Detection succeeded for Dell BIOS configuration version $ConfigVersion."
    Write-Output "Dell BIOS configuration version $ConfigVersion is installed and compliant."
    exit 0
}
catch {
    try { Write-Log "Detection failed: $($_.Exception.Message)" 'WARN' } catch { }
    exit 1
}
