<#
.SYNOPSIS
    Detects a healthy GIS Lab Check-In Helper installation for Intune.

.NOTES
    Author:  GIS Lab
    Date:    2026-09-06
    Version: 2.1
#>
[CmdletBinding()]
param()

$expectedVersion = '2.1'
$appDir = 'C:\ProgramData\UMDLibraries\GISLabForm\App'
$launcherPath = Join-Path $appDir 'Launcher-GISLabForm.ps1'
$versionPath = Join-Path $appDir 'version.txt'
$taskName = 'GIS Lab Check-In Helper'

try {
    if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) { exit 1 }
    if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) { exit 1 }
    if ((Get-Content -LiteralPath $versionPath -Raw).Trim() -ne $expectedVersion) { exit 1 }

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    if ($task.State -eq 'Disabled') { exit 1 }

    $validAction = $task.Actions | Where-Object {
        $_.Execute -match '(?i)powershell\.exe$' -and
        $_.Arguments -match [regex]::Escape($launcherPath)
    }
    $validTrigger = $task.Triggers | Where-Object {
        $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' -and $_.Enabled
    }
    if (-not $validAction -or -not $validTrigger) { exit 1 }

    Write-Output "GISLabForm $expectedVersion detected."
    exit 0
} catch {
    exit 1
}
