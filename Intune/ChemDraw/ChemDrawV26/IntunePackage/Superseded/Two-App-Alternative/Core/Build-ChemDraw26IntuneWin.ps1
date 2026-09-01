<#
.SYNOPSIS Builds the main ChemDraw 26 Intune Win32 package.
.NOTES Author: Oji / University of Maryland Libraries; Date: 2026-09-01; Version: 1.1.0
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$IntuneWinAppUtilPath
)
begin {
    $ErrorActionPreference = 'Stop'
    $packageRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $sourceRoot = Join-Path $packageRoot 'Source'
    $outputRoot = Join-Path $packageRoot 'Output'
}
process {
    if ($PSCmdlet.ShouldProcess($outputRoot,'Build main ChemDraw 26 .intunewin package')) {
        $process = Start-Process -FilePath $IntuneWinAppUtilPath -ArgumentList @('-c',('"{0}"' -f $sourceRoot),'-s','Install-ChemDraw26.ps1','-o',('"{0}"' -f $outputRoot),'-q') -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) { throw "IntuneWinAppUtil failed with exit code $($process.ExitCode)." }
        Get-ChildItem -LiteralPath $outputRoot -Filter '*.intunewin'
    }
}
