<#
.SYNOPSIS
Builds the ChemDraw Applications 26 Intune Win32 package.

.PARAMETER IntuneWinAppUtilPath
Path to Microsoft's IntuneWinAppUtil.exe.

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-09-01
Version: 1.0.0
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
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'Install-ChemDraw26Applications.ps1'))) {
        throw 'The ChemDraw Applications 26 source folder is incomplete.'
    }
    if (-not (Test-Path -LiteralPath $outputRoot)) { New-Item -Path $outputRoot -ItemType Directory -Force | Out-Null }
    if ($PSCmdlet.ShouldProcess($outputRoot, 'Build ChemDraw 26 .intunewin package')) {
        $process = Start-Process -FilePath $IntuneWinAppUtilPath -ArgumentList @('-c',('"{0}"' -f $sourceRoot),'-s','Install-ChemDraw26Applications.ps1','-o',('"{0}"' -f $outputRoot),'-q') -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) { throw "IntuneWinAppUtil failed with exit code $($process.ExitCode)." }
        Get-ChildItem -LiteralPath $outputRoot -Filter '*.intunewin' | Select-Object FullName,Length,LastWriteTime
    }
}
