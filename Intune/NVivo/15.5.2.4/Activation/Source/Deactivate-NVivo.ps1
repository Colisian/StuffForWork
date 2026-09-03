[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$nvivoPath = Join-Path $env:ProgramFiles 'QSR\NVivo 15\NVivo.exe'
$logRoot = 'C:\ProgramData\UMDLibraries\NVivo'
$logPath = Join-Path $logRoot 'Deactivate-NVivo.log'
$sentinelPath = 'HKLM:\SOFTWARE\UMDLibraries\Intune\NVivo15Activation'

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
Add-Content -LiteralPath $logPath -Value "[$([DateTime]::Now.ToString('s'))] Deactivation started."

try {
    if (-not (Test-Path -LiteralPath $sentinelPath)) {
        Add-Content -LiteralPath $logPath -Value "[$([DateTime]::Now.ToString('s'))] No managed activation sentinel was found."
        exit 0
    }
    if (-not (Test-Path -LiteralPath $nvivoPath -PathType Leaf)) {
        throw 'NVivo.exe could not be located; the license was not deactivated.'
    }

    if (-not $PSCmdlet.ShouldProcess($nvivoPath, 'Deactivate NVivo 15 license')) {
        exit 0
    }

    $process = Start-Process -FilePath $nvivoPath -ArgumentList @('-deactivate', '-skr') -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "NVivo deactivation returned exit code $($process.ExitCode)."
    }

    if ($PSCmdlet.ShouldProcess($sentinelPath, 'Remove activation completion sentinel')) {
        Remove-Item -LiteralPath $sentinelPath -Recurse -Force
    }

    Add-Content -LiteralPath $logPath -Value "[$([DateTime]::Now.ToString('s'))] Deactivation completed successfully."
    exit 0
}
catch {
    Add-Content -LiteralPath $logPath -Value "[$([DateTime]::Now.ToString('s'))] ERROR: $($_.Exception.Message)"
    Write-Error $_
    exit 1
}
