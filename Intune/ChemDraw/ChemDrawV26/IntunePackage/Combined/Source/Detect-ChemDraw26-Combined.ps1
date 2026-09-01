<#
.SYNOPSIS Detects the complete installed and activated ChemDraw 26 deployment.
.NOTES Author: Oji / University of Maryland Libraries; Date: 2026-09-01; Version: 2.0.0
#>
[CmdletBinding()]
param()
begin { $ErrorActionPreference = 'SilentlyContinue' }
process {
    $state = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\UMDLibraries\ChemDraw' -ErrorAction SilentlyContinue
    $core = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{C5C974CB-1827-47CC-9116-0B0C2B6903A2}'
    $apps64 = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{39787D88-4566-4929-9C81-A086DAEB1B21}'
    $apps32 = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{6857F9E2-AC06-471D-9777-3AB416E468CE}',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{6857F9E2-AC06-471D-9777-3AB416E468CE}'
    ) | Where-Object { Test-Path -LiteralPath $_ }
    $x86Satisfied = $state.Office32BitSupport -ne 1 -or $apps32.Count -gt 0
    if ($core -and $apps64 -and $x86Satisfied -and $state.Version -eq '26.0.0' -and $state.ActivationStatus -eq 'Activated') {
        Write-Output 'ChemDraw 26 and ChemDraw Applications are installed and activated.'
        exit 0
    }
    Write-Output 'ChemDraw 26 combined deployment is incomplete or not activated.'
    exit 1
}
