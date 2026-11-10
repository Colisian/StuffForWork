<#
.SYNOPSIS
Builds a configured SysAid Win32 package and its matching Intune detection script.
.NOTES
Author: UMD Libraries IT / Codex
Date: 2026-11-10
Version: 1.0.0
Does not install the agent or contact Intune. Build files stay in this project's Build folder.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath,
    [string]$ContentPrepTool
)
begin { $ErrorActionPreference = 'Stop' }
end {
    try {
        if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'Build\BuildConfig.json' }
        if (-not $ContentPrepTool) { $ContentPrepTool = Join-Path (Split-Path -Parent $PSScriptRoot) '.tools\IntuneWinAppUtil.exe' }
        $metadata = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Package-Metadata.json') -Raw | ConvertFrom-Json
        if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
            throw "Create $ConfigPath from SysAidConfig.example.json and enter the SysAid enrollment serial."
        }
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        if ($config.ServerUrl.TrimEnd('/') -ine $metadata.ServerUrl.TrimEnd('/') -or $config.AccountId -cne $metadata.AccountId) {
            throw 'ServerUrl or AccountId differs from Package-Metadata.json. Review the target before changing both files.'
        }
        if ([string]::IsNullOrWhiteSpace($config.Serial) -or $config.Serial -match '(?i)REPLACE_|please update|your serial') {
            throw 'Enter the enrollment serial in BuildConfig.json before building.'
        }
        $msiPath = Join-Path $PSScriptRoot $metadata.MsiFile
        if ((Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash -ne $metadata.MsiSha256) {
            throw 'MSI hash differs from the reviewed MSI. Review new MSI metadata before rebuilding.'
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $msiPath
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=SYSAID Technologies LTD') {
            throw 'A valid SysAid MSI signature is required.'
        }
        if (-not (Test-Path -LiteralPath $ContentPrepTool -PathType Leaf)) { throw "Content Prep Tool missing: $ContentPrepTool" }
        $scriptSource = Join-Path $PSScriptRoot 'Source'
        $buildDir = Join-Path $PSScriptRoot 'Build'
        $sourceDir = Join-Path $buildDir 'Source'
        $outputDir = Join-Path $buildDir 'Output'
        $intuneDir = Join-Path $PSScriptRoot 'Intune'
        foreach ($name in @('Install-SysAidAgent.ps1', 'Uninstall-SysAidAgent.ps1')) {
            if (-not (Test-Path -LiteralPath (Join-Path $scriptSource $name))) { throw "Source script missing: $name" }
        }
        if (-not $PSCmdlet.ShouldProcess($outputDir, 'Build configured SysAid Intune package')) { return }
        New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
        $builderSid = '*' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value + ':(OI)(CI)F'
        & icacls.exe $buildDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' $builderSid | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Unable to restrict the build directory.' }
        New-Item -ItemType Directory -Path $sourceDir, $outputDir, $intuneDir -Force | Out-Null
        $allowedNames = @($metadata.MsiFile, 'SysAidAgentx64.mst', 'Deployment.json', 'Install-SysAidAgent.ps1', 'Uninstall-SysAidAgent.ps1')
        if (@(Get-ChildItem -LiteralPath $sourceDir -Force | Where-Object Name -notin $allowedNames).Count) {
            throw 'Unexpected files in the build Source directory. Review them before packaging.'
        }
        foreach ($name in @('Install-SysAidAgent.ps1', 'Uninstall-SysAidAgent.ps1')) {
            Copy-Item -LiteralPath (Join-Path $scriptSource $name) -Destination (Join-Path $sourceDir $name) -Force
        }
        $packagePath = Join-Path $outputDir 'Install-SysAidAgent.intunewin'
        # Remove a stale package so a failed rebuild cannot leave an old upload appearing current.
        if (Test-Path -LiteralPath $packagePath) { Remove-Item -LiteralPath $packagePath -Force }
        Copy-Item -LiteralPath $msiPath -Destination (Join-Path $sourceDir $metadata.MsiFile) -Force
        $transformPath = Join-Path $sourceDir 'SysAidAgentx64.mst'
        & (Join-Path $PSScriptRoot 'New-SysAidTransform.ps1') -MsiPath $msiPath -ConfigPath $ConfigPath -OutputPath $transformPath -Confirm:$false
        $metadata | Add-Member -NotePropertyName TransformSha256 -NotePropertyValue (Get-FileHash -LiteralPath $transformPath -Algorithm SHA256).Hash
        $encoding = New-Object Text.UTF8Encoding($true)
        [IO.File]::WriteAllText((Join-Path $sourceDir 'Deployment.json'), ($metadata | ConvertTo-Json), $encoding)
        $template = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Templates\Detect-SysAidAgent.ps1') -Raw
        $expectedJson = $metadata | Select-Object ServerUrl, AccountId, MinimumVersion, PackageRevision | ConvertTo-Json -Compress
        $detection = $template.Replace('@@EXPECTEDJSON@@', $expectedJson.Replace("'", "''"))
        [IO.File]::WriteAllText((Join-Path $intuneDir 'Detect-SysAidAgent.ps1'), $detection, $encoding)
        # -s is mandatory for the prep tool even though PowerShell will run the actual installation.
        & $ContentPrepTool -c $sourceDir -s 'Install-SysAidAgent.ps1' -o $outputDir -q
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packagePath)) { throw 'Content Prep Tool failed.' }
        $buildInfo = [ordered]@{
            BuiltAt = (Get-Date).ToString('o')
            PackageSha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
            DetectionSha256 = (Get-FileHash -LiteralPath (Join-Path $intuneDir 'Detect-SysAidAgent.ps1') -Algorithm SHA256).Hash
            Metadata = $metadata
        }
        [IO.File]::WriteAllText((Join-Path $outputDir 'Build-Manifest.json'), ($buildInfo | ConvertTo-Json -Depth 4), $encoding)
        Write-Output "Package: $packagePath"
        Write-Output "Detection: $(Join-Path $intuneDir 'Detect-SysAidAgent.ps1')"
    } catch { Write-Error $_; exit 1 }
}
