<#
.SYNOPSIS Deactivates and uninstalls ChemDraw Applications 26.0.0.
.PARAMETER SkipDeactivation Skips the best-effort license deactivation.
.NOTES Author: Oji / University of Maryland Libraries; Date: 2026-09-01; Version: 1.1.0
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param([switch]$SkipDeactivation)
begin {
    $ErrorActionPreference = 'Stop'
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $logRoot = 'C:\ProgramData\UMDLibraries\ChemDraw\Logs'
    if (-not (Test-Path -LiteralPath $logRoot)) { New-Item -Path $logRoot -ItemType Directory -Force | Out-Null }
    $script:rebootRequired = $false
}
process {
    try {
        $activateExe = Join-Path $scriptDir 'Revvity\Activation\Activate.exe'
        if (-not $SkipDeactivation -and (Test-Path -LiteralPath $activateExe) -and $PSCmdlet.ShouldProcess('ChemDraw 26 license','Deactivate')) {
            $deactivate = Start-Process -FilePath $activateExe -ArgumentList @('26.0','Deactivate','Silent') -Wait -PassThru -WindowStyle Hidden
            if ($deactivate.ExitCode -ne 0) { Write-Warning 'License deactivation failed; obsolete the device in the Revvity portal if needed.' }
        }
        $msiexec = Join-Path $env:WINDIR 'System32\msiexec.exe'
        foreach ($code in @('{6857F9E2-AC06-471D-9777-3AB416E468CE}','{39787D88-4566-4929-9C81-A086DAEB1B21}')) {
            if ($PSCmdlet.ShouldProcess($code,'Uninstall ChemDraw Applications MSI')) {
                $log = Join-Path $logRoot ("Uninstall-$($code.Trim('{}')).log")
                $process = Start-Process -FilePath $msiexec -ArgumentList @('/x',$code,'/qn','REBOOT=ReallySuppress','/L*v',('"{0}"' -f $log)) -Wait -PassThru -WindowStyle Hidden
                if ($process.ExitCode -in @(1641,3010)) { $script:rebootRequired = $true }
                elseif ($process.ExitCode -notin @(0,1605)) { throw "Applications MSI uninstall failed with exit code $($process.ExitCode)." }
            }
        }
        $sentinel = 'HKLM:\SOFTWARE\UMDLibraries\ChemDraw'
        if (Test-Path -LiteralPath $sentinel) { Remove-ItemProperty -LiteralPath $sentinel -Name ApplicationsVersion,ActivationStatus,ActivationDateUtc,Office32BitSupport -ErrorAction SilentlyContinue }
        if ($script:rebootRequired) { exit 3010 }
        exit 0
    } catch { Write-Error $_.Exception.Message; exit 1 }
}
