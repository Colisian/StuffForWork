<#
.SYNOPSIS
Deactivates and uninstalls the complete ChemDraw 26 deployment.

.DESCRIPTION
Designed for Intune's native PowerShell uninstall field or a normal -File call.
Removes ChemDraw Applications first, then the main ChemDraw product.

.PARAMETER SkipDeactivation
Skips the best-effort online license deactivation.

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-09-01
Version: 2.0.0
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param([switch]$SkipDeactivation)

begin {
    $ErrorActionPreference = 'Stop'
    $componentRoot = 'C:\ProgramData\UMDLibraries\ChemDraw'
    $logRoot = Join-Path $componentRoot 'Logs'
    if (-not (Test-Path -LiteralPath $logRoot)) { New-Item -Path $logRoot -ItemType Directory -Force | Out-Null }
    $logPath = Join-Path $logRoot ("Uninstall-ChemDraw26-Combined_{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $logPath -Force | Out-Null
    $script:rebootRequired = $false

    function Resolve-PackageRoot {
        <# .SYNOPSIS Finds the unpacked Intune content directory. .NOTES Author: Oji; Date: 2026-09-01; Version: 2.0.0 #>
        [CmdletBinding()]
        param()
        $candidates = @()
        if ($PSScriptRoot) { $candidates += $PSScriptRoot }
        $candidates += (Get-Location).Path
        foreach ($candidate in @($candidates | Select-Object -Unique)) {
            if (Test-Path -LiteralPath (Join-Path $candidate 'PackageMarker.txt') -PathType Leaf) { return $candidate }
        }
        throw 'Unable to locate PackageMarker.txt in the script directory or current package directory.'
    }

    function Invoke-UninstallProcess {
        <# .SYNOPSIS Runs an uninstall process and validates its exit code. .NOTES Author: Oji; Date: 2026-09-01; Version: 2.0.0 #>
        [CmdletBinding(SupportsShouldProcess = $true)]
        param([Parameter(Mandatory)][string]$FilePath,[string[]]$ArgumentList,[int[]]$SuccessCodes=@(0),[string]$WorkingDirectory)
        if (-not $WorkingDirectory) { $WorkingDirectory = $script:packageRoot }
        Write-Output ("{0:u} Running: {1} {2}" -f (Get-Date),$FilePath,($ArgumentList -join ' '))
        if (-not $PSCmdlet.ShouldProcess($FilePath,'Run uninstall process')) { return 0 }
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -Wait -PassThru -WindowStyle Hidden
        $exitCode = [int]$process.ExitCode
        if ($exitCode -in @(1641,3010)) { $script:rebootRequired = $true }
        if ($exitCode -notin $SuccessCodes) { throw "Process failed with exit code $exitCode`: $FilePath" }
        return $exitCode
    }
}

process {
    $exitCode = 0
    try {
        $script:packageRoot = Resolve-PackageRoot
        $activation = Join-Path $script:packageRoot 'Revvity\Activation'
        $activateExe = Join-Path $activation 'Activate.exe'
        if (-not $SkipDeactivation -and (Test-Path -LiteralPath $activateExe)) {
            try { Invoke-UninstallProcess -FilePath $activateExe -ArgumentList @('26.0','Deactivate','Silent') -WorkingDirectory $activation -SuccessCodes @(0) | Out-Null }
            catch { Write-Warning 'License deactivation failed; obsolete the device in the Revvity portal if the seat is not returned.' }
        }

        $msiexec = Join-Path $env:WINDIR 'System32\msiexec.exe'
        $productCodes = @(
            '{6857F9E2-AC06-471D-9777-3AB416E468CE}',
            '{39787D88-4566-4929-9C81-A086DAEB1B21}',
            '{C5C974CB-1827-47CC-9116-0B0C2B6903A2}'
        )
        foreach ($productCode in $productCodes) {
            $msiLog = Join-Path $logRoot ("Uninstall-{0}.log" -f $productCode.Trim('{}'))
            Invoke-UninstallProcess -FilePath $msiexec -ArgumentList @('/x',$productCode,'/qn','REBOOT=ReallySuppress','/L*v',('"{0}"' -f $msiLog)) -SuccessCodes @(0,1605,1641,3010) | Out-Null
        }

        $sentinel = 'HKLM:\SOFTWARE\UMDLibraries\ChemDraw'
        if (Test-Path -LiteralPath $sentinel) { Remove-Item -LiteralPath $sentinel -Recurse -Force }
        Write-Output 'ChemDraw 26 combined uninstall completed.'
        if ($script:rebootRequired) { $exitCode = 3010 }
    } catch { Write-Error $_.Exception.Message; $exitCode = 1 }
    finally { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null }
    exit $exitCode
}
