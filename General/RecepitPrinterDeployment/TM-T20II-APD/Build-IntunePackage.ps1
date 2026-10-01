<#
.SYNOPSIS
    Builds the .intunewin for the Epson TM-T20II APD5 deployment.

.DESCRIPTION
    Extracts APD_513_T20II.exe from the Epson download zip, stages it with the
    install/uninstall scripts in a clean Source folder, and runs IntuneWinAppUtil.
    Binaries stay out of the git repo; only the scripts are versioned here.

.PARAMETER DriverZip
    Path to the Epson APD zip (APD_513_T20II_EWM.zip).

.PARAMETER WorkRoot
    Folder that receives Source\ and Output\.

.PARAMETER IntuneWinAppUtil
    Path to IntuneWinAppUtil.exe.

.EXAMPLE
    .\Build-IntunePackage.ps1

.EXAMPLE
    .\Build-IntunePackage.ps1 -WhatIf

.NOTES
    Author:  Oji
    Date:    2026-09-28
    Version: 4.0.0
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DriverZip = "$env:USERPROFILE\OneDrive - University of Maryland\Documents\Work\Intune\1-InstallationFiles\Epson Receipt Printer\APD_513_T20II_EWM.zip",
    [string]$WorkRoot = "$env:USERPROFILE\OneDrive - University of Maryland\Documents\Work\Intune\2-IntuneApps\EpsonTMT20II-APD",
    [string]$IntuneWinAppUtil = "$env:USERPROFILE\OneDrive - University of Maryland\Documents\Work\Intune\3.5-Microsoft-Win32-Content-Prep-Tool-master\IntuneWinAppUtil.exe"
)

begin {
    $ErrorActionPreference = 'Stop'
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $sourceDir = Join-Path $WorkRoot 'Source'
    $outputDir = Join-Path $WorkRoot 'Output'
    $scripts   = 'Install-EpsonTMT20II.ps1', 'Uninstall-EpsonTMT20II.ps1'
}

end {
    foreach ($path in $DriverZip, $IntuneWinAppUtil) {
        if (-not (Test-Path $path)) { throw "Not found: $path" }
    }

    if ($PSCmdlet.ShouldProcess($sourceDir, 'Rebuild Source folder')) {
        if (Test-Path $sourceDir) { Remove-Item $sourceDir -Recurse -Force }
        New-Item -Path $sourceDir -ItemType Directory -Force | Out-Null
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

        # Pull only the installer EXE out of the Epson zip (manual/PDF not needed on endpoints)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($DriverZip)
        try {
            $entry = $zip.Entries | Where-Object { $_.Name -like 'APD_5*_T20II.exe' } | Select-Object -First 1
            if (-not $entry) { throw "APD_5*_T20II.exe not found inside $DriverZip" }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $sourceDir $entry.Name), $true)
        }
        finally { $zip.Dispose() }

        $signature = Get-AuthenticodeSignature (Join-Path $sourceDir $entry.Name)
        Write-Host "Installer signature: $($signature.Status) - $($signature.SignerCertificate.Subject)"
        if ($signature.Status -ne 'Valid') { throw 'Epson installer signature is not valid - aborting' }

        foreach ($s in $scripts) { Copy-Item (Join-Path $ScriptDir $s) $sourceDir -Force }

        # Epson copy-installation script (.inf) exported from the reference PC - see runbook
        $copyScripts = @(Get-ChildItem -Path (Join-Path $ScriptDir 'CopyScript') -Filter '*.inf' -File -ErrorAction SilentlyContinue)
        if ($copyScripts.Count -ne 1) {
            throw "Expected exactly one Epson copy script in $(Join-Path $ScriptDir 'CopyScript'), found $($copyScripts.Count). Export it from the reference PC first."
        }
        Copy-Item $copyScripts[0].FullName $sourceDir -Force
        Write-Host "Copy script: $($copyScripts[0].Name)"
    }

    if ($PSCmdlet.ShouldProcess($outputDir, 'Run IntuneWinAppUtil')) {
        & $IntuneWinAppUtil -c $sourceDir -s 'Install-EpsonTMT20II.ps1' -o $outputDir -q
        if ($LASTEXITCODE -ne 0) { throw "IntuneWinAppUtil exited $LASTEXITCODE" }
        Get-ChildItem $outputDir -Filter *.intunewin | Select-Object Name, Length, LastWriteTime
    }
}
