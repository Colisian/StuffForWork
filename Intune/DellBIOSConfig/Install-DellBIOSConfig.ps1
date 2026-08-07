#requires -Version 5.1
<#
.SYNOPSIS
    Configures the approved Dell BIOS settings through Dell Command | Configure.

.DESCRIPTION
    Intended for an Intune Win32 app running as SYSTEM in 64-bit Windows PowerShell.
    Dell Command | Configure 5.2.2.292 (or a compatible 5.x release) must already
    be installed. This version does not create, clear, or supply a BIOS setup/admin
    password. It is intended for new Dell devices that have no existing setup
    password. Dell Command | Configure rejects protected setting changes when an
    existing password is present, so those devices fail without changing the marker.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ConfigVersion = '1.0.0'
$LogRoot = Join-Path $env:ProgramData 'Dell\BIOSConfig'
$RegistryPath = 'HKLM:\SOFTWARE\StuffForWork\DellBIOSConfig'
$TimeStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogRoot "Install-DellBIOSConfig-$TimeStamp.log"

function Write-Log {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')

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
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'Dell Command | Configure cctk.exe was not found. Install Dell Command | Configure before this app runs.'
}

function Invoke-Cctk {
    param(
        [Parameter(Mandatory)][string]$Cctk,
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $cctkLog = Join-Path $LogRoot ('cctk-{0}-{1}-{2}.log' -f $Operation, (Get-Date -Format 'yyyyMMdd-HHmmssfff'), ([guid]::NewGuid().ToString('N').Substring(0, 6)))
    $allArguments = @($Arguments) + ("-l=$cctkLog")
    Write-Log ("CCTK {0}: {1}" -f $Operation, ($allArguments -join ' '))

    $output = @(& $Cctk @allArguments 2>&1)
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        Write-Log ("CCTK {0} output: {1}" -f $Operation, $line)
    }
    Write-Log ("CCTK {0} exit code: {1}" -f $Operation, $exitCode)

    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output   = @($output | ForEach-Object { [string]$_ })
        LogFile  = $cctkLog
    }
}

function Get-CctkSetting {
    param(
        [Parameter(Mandatory)][string]$Cctk,
        [Parameter(Mandatory)][string]$Option,
        [Parameter(Mandatory)][string]$OutputName
    )

    $result = Invoke-Cctk -Cctk $Cctk -Operation ("Read-{0}" -f $OutputName) -Arguments @("--$Option")
    if ($result.ExitCode -ne 0) {
        throw "Unable to read BIOS setting $OutputName. Dell CCTK exit code: $($result.ExitCode)."
    }

    $pattern = '^(?i:{0})\s*=\s*(.+?)\s*$' -f [regex]::Escape($OutputName)
    $match = $result.Output | ForEach-Object { [regex]::Match($_, $pattern) } | Where-Object { $_.Success } | Select-Object -Last 1
    if ($null -eq $match) {
        throw "CCTK did not return a readable value for BIOS setting $OutputName."
    }
    return $match.Groups[1].Value.Trim()
}

function Set-RegistryMarker {
    param(
        [Parameter(Mandatory)][string]$Cctk,
        [Parameter(Mandatory)][hashtable]$AppliedSettings,
        [Parameter(Mandatory)][string]$PasswordState,
        [string]$CctkVersion
    )

    New-Item -Path $RegistryPath -Force | Out-Null
    $properties = @{
        Version       = $ConfigVersion
        State         = 'Compliant'
        AppliedUtc    = (Get-Date).ToUniversalTime().ToString('o')
        CctkPath      = $Cctk
        CctkVersion   = $CctkVersion
        PasswordState = $PasswordState
        SettingsJson  = ($AppliedSettings | ConvertTo-Json -Compress)
    }
    foreach ($property in $properties.GetEnumerator()) {
        New-ItemProperty -Path $RegistryPath -Name $property.Key -Value $property.Value -PropertyType String -Force | Out-Null
    }
}

try {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Write-Log "Starting Dell BIOS configuration deployment version $ConfigVersion."

    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($computerSystem.Manufacturer -notmatch '(?i)dell') {
        Write-Log "Device manufacturer '$($computerSystem.Manufacturer)' is not Dell. No BIOS changes were made." 'WARN'
        exit 0
    }
    Write-Log "Dell hardware detected: model '$($computerSystem.Model)'."

    $cctk = Get-CctkPath
    $versionResult = Invoke-Cctk -Cctk $cctk -Operation 'Version' -Arguments @('--Version')
    if ($versionResult.ExitCode -ne 0) {
        throw "CCTK could not report its version. Dell CCTK exit code: $($versionResult.ExitCode)."
    }
    $cctkVersion = ($versionResult.Output -join ' ').Trim()
    Write-Log "Using cctk.exe: $cctk. Version output: $cctkVersion"

    $desiredSettings = @(
        [pscustomobject]@{ OutputName = 'WakeOnLan';  CctkOption = 'WakeonLAN'; DesiredValue = 'LanOnly' },
        [pscustomobject]@{ OutputName = 'AcPwrRcvry'; CctkOption = 'AcPwrRcvry'; DesiredValue = 'Last' },
        # AutoOn must be enabled before its hour and minute properties can be configured.
        [pscustomobject]@{ OutputName = 'AutoOn';     CctkOption = 'AutoOn';     DesiredValue = 'Everyday' },
        [pscustomobject]@{ OutputName = 'AutoOnHr';   CctkOption = 'AutoOnHr';   DesiredValue = '6' },
        [pscustomobject]@{ OutputName = 'AutoOnMn';   CctkOption = 'AutoOnMn';   DesiredValue = '0' }
    )

    foreach ($setting in $desiredSettings) {
        $currentValue = Get-CctkSetting -Cctk $cctk -Option $setting.CctkOption -OutputName $setting.OutputName
        if ($currentValue -ieq $setting.DesiredValue) {
            Write-Log "$($setting.OutputName) is already '$($setting.DesiredValue)'."
            continue
        }

        Write-Log "Changing $($setting.OutputName) from '$currentValue' to '$($setting.DesiredValue)'."
        $setResult = Invoke-Cctk -Cctk $cctk -Operation ("Set-{0}" -f $setting.OutputName) -Arguments @("--$($setting.CctkOption)=$($setting.DesiredValue)")
        if ($setResult.ExitCode -ne 0) {
            throw "Failed to set $($setting.OutputName). Dell CCTK exit code: $($setResult.ExitCode)."
        }
    }

    # Read every requested setting again. The registry marker is written only after this succeeds.
    $verifiedSettings = @{}
    foreach ($setting in $desiredSettings) {
        $actualValue = Get-CctkSetting -Cctk $cctk -Option $setting.CctkOption -OutputName $setting.OutputName
        if ($actualValue -ine $setting.DesiredValue) {
            throw "Post-apply verification failed for $($setting.OutputName). Expected '$($setting.DesiredValue)', received '$actualValue'."
        }
        $verifiedSettings[$setting.OutputName] = $actualValue
    }

    Set-RegistryMarker -Cctk $cctk -AppliedSettings $verifiedSettings -PasswordState 'NotConfigured' -CctkVersion $cctkVersion
    Write-Log "Dell BIOS configuration version $ConfigVersion completed and verified successfully."
    exit 0
}
catch {
    try {
        if (-not (Test-Path -LiteralPath $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
        Write-Log "Deployment failed: $($_.Exception.Message)" 'ERROR'
    }
    catch { }
    exit 1
}
