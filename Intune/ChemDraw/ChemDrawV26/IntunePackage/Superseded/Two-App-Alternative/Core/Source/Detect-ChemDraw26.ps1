<#
.SYNOPSIS Detects the main ChemDraw 26.0.0 installation for Intune.
.NOTES Author: Oji / University of Maryland Libraries; Date: 2026-09-01; Version: 1.1.0
#>
[CmdletBinding()]
param()
begin { $ErrorActionPreference = 'SilentlyContinue' }
process {
    $sentinel = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\UMDLibraries\ChemDraw' -ErrorAction SilentlyContinue
    $msiKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{C5C974CB-1827-47CC-9116-0B0C2B6903A2}'
    if ((Test-Path -LiteralPath $msiKey) -and $sentinel.CoreVersion -eq '26.0.0') {
        Write-Output 'Main ChemDraw 26.0.0 is installed.'
        exit 0
    }
    Write-Output 'Main ChemDraw 26.0.0 is not installed.'
    exit 1
}
