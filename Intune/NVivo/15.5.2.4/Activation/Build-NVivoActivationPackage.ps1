[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ContentPrepTool = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) '.tools\IntuneWinAppUtil.exe')
)

$ErrorActionPreference = 'Stop'
$sourceDir = Join-Path $PSScriptRoot 'Source'
$outputDir = Join-Path $PSScriptRoot 'Output'
$requiredFiles = @(
    'Activate-NVivo.ps1',
    'Deactivate-NVivo.ps1',
    'Detect-NVivoActivation.ps1',
    'Activation.xml',
    'NVivoLicense.ps1'
)

foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceDir $file) -PathType Leaf)) {
        throw "Required source file is missing: $file"
    }
}

if (-not (Test-Path -LiteralPath $ContentPrepTool -PathType Leaf)) {
    throw "Microsoft Win32 Content Prep Tool not found: $ContentPrepTool"
}

# PRODUCT KEY LOCATION:
# Store the key only in Source\NVivoLicense.ps1. That file is excluded by the
# Intune\.gitignore file but is deliberately included in the .intunewin package.
if (-not $PSCmdlet.ShouldProcess($outputDir, 'Build NVivo activation package')) {
    return
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
& $ContentPrepTool -c $sourceDir -s 'Activate-NVivo.ps1' -o $outputDir -q
if ($LASTEXITCODE -ne 0) {
    throw "IntuneWinAppUtil failed with exit code $LASTEXITCODE."
}

$packagePath = Join-Path $outputDir 'Activate-NVivo.intunewin'
if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw "Expected package was not created: $packagePath"
}

Get-Item -LiteralPath $packagePath | Select-Object FullName,Length,LastWriteTime
