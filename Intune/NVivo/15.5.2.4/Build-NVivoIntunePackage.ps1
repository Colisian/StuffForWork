[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ContentPrepTool = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.tools\IntuneWinAppUtil.exe')
)

$ErrorActionPreference = 'Stop'
$sourceDir = Join-Path $PSScriptRoot 'Source'
$outputDir = Join-Path $PSScriptRoot 'Output'
$setupFile = 'Install-NVivo.ps1'
$requiredFiles = @(
    'NVivo.x64.exe',
    'Install-NVivo.ps1',
    'Uninstall-NVivo.ps1',
    'Detect-NVivo.ps1'
)

foreach ($file in $requiredFiles) {
    $path = Join-Path $sourceDir $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required package file is missing: $path"
    }
}

if (-not (Test-Path -LiteralPath $ContentPrepTool -PathType Leaf)) {
    throw "Microsoft Win32 Content Prep Tool not found: $ContentPrepTool"
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
if ($PSCmdlet.ShouldProcess($outputDir, 'Create NVivo .intunewin package')) {
    & $ContentPrepTool -c $sourceDir -s $setupFile -o $outputDir -q
    if ($LASTEXITCODE -ne 0) {
        throw "IntuneWinAppUtil failed with exit code $LASTEXITCODE."
    }
}

$packagePath = Join-Path $outputDir 'Install-NVivo.intunewin'
if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw "Expected package was not created: $packagePath"
}

Get-Item -LiteralPath $packagePath | Select-Object FullName, Length, LastWriteTime
