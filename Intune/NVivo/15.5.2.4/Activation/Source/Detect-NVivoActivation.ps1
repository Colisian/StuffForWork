[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'
$sentinelPath = 'HKLM:\SOFTWARE\UMDLibraries\Intune\NVivo15Activation'
$nvivoPath = Join-Path $env:ProgramFiles 'QSR\NVivo 15\NVivo.exe'
$requiredPackageVersion = '1.0.0'

$sentinel = Get-ItemProperty -Path $sentinelPath
if (-not (Test-Path -LiteralPath $nvivoPath -PathType Leaf)) {
    Write-Output 'NVivo 15 is not installed.'
    exit 1
}
if (-not $sentinel -or $sentinel.PackageVersion -ne $requiredPackageVersion) {
    Write-Output 'The managed NVivo activation sentinel is missing or outdated.'
    exit 1
}
if ($sentinel.KeyFingerprint -notmatch '^[A-F0-9]{64}$') {
    Write-Output 'The managed NVivo activation fingerprint is invalid.'
    exit 1
}

Write-Output 'NVivo 15 managed activation completed.'
exit 0
