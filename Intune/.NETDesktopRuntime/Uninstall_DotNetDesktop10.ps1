$ErrorActionPreference = 'Stop'
$Installer = 'windowsdesktop-runtime-10.0.9-win-x64.exe'
$LogDir    = "$env:ProgramData\IntuneLogs"
$IntuneLog = Join-Path $LogDir 'DotNetDesktop10-Uninstall.log'

if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message" | Tee-Object -FilePath $IntuneLog -Append
}

$exePath = Join-Path $PSScriptRoot $Installer
Write-Log "=== Uninstalling $Installer ==="

$proc = Start-Process -FilePath $exePath `
    -ArgumentList "/uninstall /quiet /norestart" -Wait -PassThru
$rc = $proc.ExitCode
Write-Log "Uninstall exit code: $rc"

switch ($rc) {
    0     { exit 0 }
    3010  { exit 3010 }
    default { exit $rc }
}