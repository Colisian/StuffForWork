<#
.SYNOPSIS Builds the single combined ChemDraw 26 Intune Win32 package.
.NOTES Author: Oji / University of Maryland Libraries; Date: 2026-09-01; Version: 2.0.0
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
    foreach ($required in @('PackageMarker.txt','Install-ChemDraw26-IntuneNative.ps1','Uninstall-ChemDraw26-IntuneNative.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $required))) { throw "Combined source is missing $required" }
    }
    if ($PSCmdlet.ShouldProcess($outputRoot,'Build combined ChemDraw 26 .intunewin package')) {
        $process = Start-Process -FilePath $IntuneWinAppUtilPath -ArgumentList @('-c',('"{0}"' -f $sourceRoot),'-s','PackageMarker.txt','-o',('"{0}"' -f $outputRoot),'-q') -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) { throw "IntuneWinAppUtil failed with exit code $($process.ExitCode)." }
        $generated = Join-Path $outputRoot 'PackageMarker.intunewin'
        $final = Join-Path $outputRoot 'ChemDraw26-Combined.intunewin'
        if (-not (Test-Path -LiteralPath $generated)) { throw 'Expected PackageMarker.intunewin was not generated.' }
        Move-Item -LiteralPath $generated -Destination $final -Force
        Get-Item -LiteralPath $final
    }
}
