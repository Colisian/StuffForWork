[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Security.SecureString]$LicenseKey,
    [string]$ContentPrepTool = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) '.tools\IntuneWinAppUtil.exe')
)

$ErrorActionPreference = 'Stop'
$sourceDir = Join-Path $PSScriptRoot 'Source'
$outputDir = Join-Path $PSScriptRoot 'Output'
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$stagingDir = Join-Path $temporaryRoot ("NVivoActivation-{0}" -f [guid]::NewGuid())
$bstr = [IntPtr]::Zero
$plainTextKey = $null

if (-not $LicenseKey) {
    # PRODUCT KEY ENTRY POINT:
    # Run this build script and paste the new NVivo product key into the secure
    # prompt below. The characters will not appear on screen. Do not paste the
    # key into Activate-NVivo.ps1, Activation.xml, or any file under Source.
    $LicenseKey = Read-Host 'Enter the NVivo enterprise key' -AsSecureString
}

try {
    foreach ($file in @('Activate-NVivo.ps1', 'Deactivate-NVivo.ps1', 'Detect-NVivoActivation.ps1', 'Activation.xml')) {
        if (-not (Test-Path -LiteralPath (Join-Path $sourceDir $file) -PathType Leaf)) {
            throw "Required source file is missing: $file"
        }
    }
    if (-not (Test-Path -LiteralPath $ContentPrepTool -PathType Leaf)) {
        throw "Microsoft Win32 Content Prep Tool not found: $ContentPrepTool"
    }
    if (-not $PSCmdlet.ShouldProcess($outputDir, 'Build protected NVivo activation package')) {
        return
    }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($LicenseKey)
    $plainTextKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    if ($plainTextKey -notmatch '^[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}$') {
        throw 'The supplied NVivo key does not match the expected format.'
    }

    New-Item -ItemType Directory -Path $stagingDir,$outputDir -Force | Out-Null
    Copy-Item -Path (Join-Path $sourceDir '*') -Destination $stagingDir -Recurse -Force
    $utf8NoBom = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $stagingDir 'NVivoLicense.key'), $plainTextKey, $utf8NoBom)

    & $ContentPrepTool -c $stagingDir -s 'Activate-NVivo.ps1' -o $outputDir -q
    if ($LASTEXITCODE -ne 0) {
        throw "IntuneWinAppUtil failed with exit code $LASTEXITCODE."
    }

    $packagePath = Join-Path $outputDir 'Activate-NVivo.intunewin'
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
        throw "Expected package was not created: $packagePath"
    }

    Get-Item -LiteralPath $packagePath | Select-Object FullName,Length,LastWriteTime
}
finally {
    $plainTextKey = $null
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }

    $resolvedStage = [IO.Path]::GetFullPath($stagingDir)
    if ($resolvedStage.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedStage) -like 'NVivoActivation-*' -and
        (Test-Path -LiteralPath $resolvedStage)) {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
