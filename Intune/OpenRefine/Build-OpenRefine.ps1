<#
.SYNOPSIS
Stages and builds the OpenRefine Intune Win32 package without installing the application.
.NOTES
Author: UMD Libraries IT
Date: 2026-11-17
Version: 1.0.0
Output remains outside the staged Package folder to prevent recursive packaging.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$InstallerPath = 'C:\Users\cmcleod1\OneDrive - University of Maryland\Documents\Work\Intune\1-InstallationFiles\OpenRefine\OpenRefine 3.10\openrefine.exe',
    [string]$ContentPrepTool = 'C:\Users\cmcleod1\OneDrive - University of Maryland\Documents\Work\Intune\3.5-Microsoft-Win32-Content-Prep-Tool-master\IntuneWinAppUtil.exe'
)
begin { $ErrorActionPreference = 'Stop' }
process {
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $transcribing = $false
    try {
        $config = Get-Content -LiteralPath (Join-Path $ScriptDir 'OpenRefine.config.json') -Raw | ConvertFrom-Json
        if ((Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash -ne $config.SHA256) {
            throw 'Installer hash mismatch. Review the release and configuration before rebuilding.'
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $ContentPrepTool
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
            throw 'The content prep tool must have a valid Microsoft signature.'
        }
        $packageDirectory = Join-Path $ScriptDir 'Package'
        $outputDirectory = Join-Path $ScriptDir 'Output'
        $bundled = @('Install-OpenRefine.ps1', 'Uninstall-OpenRefine.ps1', 'OpenRefine.Common.ps1', 'OpenRefine.config.json')
        foreach ($name in $bundled) {
            if (-not (Test-Path -LiteralPath (Join-Path $ScriptDir $name) -PathType Leaf)) { throw "Missing $name." }
        }
        if (Test-Path -LiteralPath $packageDirectory) {
            $extra = @(Get-ChildItem -LiteralPath $packageDirectory -Force | Where-Object {
                $_.Name -notin ($bundled + $config.InstallerFile) -or $_.PSIsContainer
            })
            if ($extra.Count) { throw 'Package contains unexpected content. Review it before rebuilding.' }
        }
        if (-not $PSCmdlet.ShouldProcess($outputDirectory, 'Stage OpenRefine and build Intune Win32 package')) { return }
        New-Item -Path $packageDirectory, $outputDirectory -ItemType Directory -Force | Out-Null
        Start-Transcript -Path (Join-Path $outputDirectory 'Build-OpenRefine.log') -Append | Out-Null
        $transcribing = $true
        foreach ($name in $bundled) {
            Copy-Item -LiteralPath (Join-Path $ScriptDir $name) -Destination (Join-Path $packageDirectory $name) -Force
        }
        Copy-Item -LiteralPath $InstallerPath -Destination (Join-Path $packageDirectory $config.InstallerFile) -Force
        & $ContentPrepTool -c $packageDirectory -s 'Install-OpenRefine.ps1' -o $outputDirectory -q
        if ($LASTEXITCODE -ne 0) { throw "Content prep tool failed with exit code $LASTEXITCODE." }
        $result = Get-Item -LiteralPath (Join-Path $outputDirectory 'Install-OpenRefine.intunewin')
        if ($result.Length -le 0) { throw 'The generated package is empty.' }
        $receipt = [ordered]@{
            BuiltAt = (Get-Date -Format o)
            ApplicationVersion = $config.Version
            InstallerSHA256 = $config.SHA256
            ContentPrepToolVersion = (Get-Item -LiteralPath $ContentPrepTool).VersionInfo.FileVersion
            PackageFile = $result.Name
            PackageBytes = $result.Length
            PackageSHA256 = (Get-FileHash -LiteralPath $result.FullName -Algorithm SHA256).Hash
        }
        $receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputDirectory 'Build-Receipt.json') -Encoding UTF8
        Write-Output "Created $($result.FullName)"
    }
    catch { Write-Output "ERROR: $($_.Exception.Message)"; exit 1 }
    finally { if ($transcribing) { Stop-Transcript | Out-Null } }
}
