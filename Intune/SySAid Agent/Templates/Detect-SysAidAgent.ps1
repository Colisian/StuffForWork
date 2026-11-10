<#
.SYNOPSIS
Detects the configured UMD Libraries SysAid installation for Intune.
.NOTES
Author: UMD Libraries IT / Codex
Date: 2026-11-10
Version: 1.0.0
Build generates Intune/Detect-SysAidAgent.ps1. Upload that generated file, not this template.
Service health and server check-in are separate from application installation detection.
#>
[CmdletBinding()]
param()
begin { $ErrorActionPreference = 'Stop' }
end {
    $hklm = $null
    $agent = $null
    $marker = $null
    try {
        $expected = ConvertFrom-Json -InputObject '@@EXPECTEDJSON@@'
        # Explicit registry view makes detection safe even if Intune runs a 32-bit host.
        $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
        $agent = $hklm.OpenSubKey('SOFTWARE\SysAid\InstalledProducts\SysAid')
        $marker = $hklm.OpenSubKey('SOFTWARE\UMDLibraries\SysAidAgent')
        if (-not $agent -or -not $marker) { exit 1 }
        if ([int]$marker.GetValue('PackageRevision', 0) -lt [int]$expected.PackageRevision) { exit 1 }
        foreach ($key in @($agent, $marker)) {
            if (([string]$key.GetValue('ServerUrl', '')).TrimEnd('/') -ine $expected.ServerUrl.TrimEnd('/') -or
                [string]$key.GetValue('AccountId', '') -cne $expected.AccountId) { exit 1 }
        }
        if ([version]$agent.GetValue('DisplayVersion', '0.0') -lt [version]$expected.MinimumVersion) { exit 1 }
        $location = [string]$agent.GetValue('InstallLocation', '')
        if (-not $location -or -not (Test-Path -LiteralPath (Join-Path $location 'SysAidAgent.exe') -PathType Leaf)) { exit 1 }
        if (-not (Get-Service -Name 'SysAidAgent' -ErrorAction SilentlyContinue)) { exit 1 }
        Write-Output 'UMD Libraries SysAid Agent detected.'
        exit 0
    } catch { exit 1 }
    finally {
        foreach ($key in @($marker, $agent, $hklm)) { if ($key) { $key.Dispose() } }
    }
}
