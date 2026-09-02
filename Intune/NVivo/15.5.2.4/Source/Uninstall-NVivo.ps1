[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$logRoot = 'C:\ProgramData\UMDLibraries\NVivo'
$wrapperLog = Join-Path $logRoot 'Uninstall-NVivo.log'
$msiLog = Join-Path $logRoot 'Uninstall-NVivo-MSI.log'
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
            $_.DisplayVersion -match '^15(?:\.|$)'
        } |
        Sort-Object PSPath -Unique
}

function Split-UninstallCommand {
    <#
    .SYNOPSIS
    Separates a registered uninstall command into executable and arguments.
    .NOTES
    Author: University of Maryland Libraries ITFO
    Date: 2026-09-02
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandLine
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ($expanded -match '^"(?<file>[^"]+\.exe)"\s*(?<args>.*)$') {
        return [pscustomobject]@{ FilePath = $Matches.file; Arguments = $Matches.args }
    }
    if ($expanded -match '^(?<file>.+?\.exe)\s*(?<args>.*)$') {
        return [pscustomobject]@{ FilePath = $Matches.file; Arguments = $Matches.args }
    }

    throw "Unable to parse uninstall command: $CommandLine"
}

function Invoke-NVivoRemoval {
    <#
    .SYNOPSIS
    Silently removes one registered NVivo 15 product.
    .NOTES
    Author: University of Maryland Libraries ITFO
    Date: 2026-09-02
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [psobject]$Registration
    )

    $productCode = $Registration.PSChildName
    if ($productCode -match '^\{[0-9A-Fa-f-]{36}\}$') {
        $filePath = Join-Path $env:SystemRoot 'System32\msiexec.exe'
        $arguments = "/x $productCode /qn /norestart /L*v `"$msiLog`""
    }
    elseif ($Registration.QuietUninstallString) {
        $command = Split-UninstallCommand -CommandLine $Registration.QuietUninstallString
        $filePath = $command.FilePath
        $arguments = $command.Arguments
    }
    else {
        throw "No safe silent uninstall command was registered for $($Registration.DisplayName)."
    }

    if (-not $PSCmdlet.ShouldProcess($Registration.DisplayName, 'Uninstall silently')) {
        return 0
    }

    $process = Start-Process -FilePath $filePath -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0, 1605, 1614, 1641, 3010)) {
        throw "Uninstall returned exit code $($process.ExitCode)."
    }

    return $process.ExitCode
}

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
Start-Transcript -Path $wrapperLog -Append | Out-Null

try {
    $registrations = @(Get-NVivoRegistration)
    $resultCode = 0

    foreach ($registration in $registrations) {
        $exitCode = Invoke-NVivoRemoval -Registration $registration
        if ($exitCode -in @(1641, 3010)) {
            $resultCode = 3010
        }
    }

    if (Get-NVivoRegistration) {
        throw 'NVivo 15 is still registered after the uninstall attempt.'
    }

    if ($PSCmdlet.ShouldProcess($sentinelPath, 'Remove NVivo Intune detection sentinel')) {
        Remove-Item -Path $sentinelPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Output 'NVivo 15 removal completed.'
    exit $resultCode
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
