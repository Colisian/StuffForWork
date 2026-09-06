<#
.SYNOPSIS
    Uninstalls the GIS Lab Check-In Helper.

.DESCRIPTION
    Stops GIS Lab launcher and kiosk processes, removes the scheduled task and
    application files, and preserves deployment logs for troubleshooting.

.NOTES
    Author:  GIS Lab
    Date:    2026-09-06
    Version: 2.1
    Log:     C:\ProgramData\UMDLibraries\GISLabForm\DeploymentLogs\uninstall.log
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$taskName = 'GIS Lab Check-In Helper'
$rootDir = 'C:\ProgramData\UMDLibraries\GISLabForm'
$appDir = Join-Path $rootDir 'App'
$deploymentLogDir = Join-Path $rootDir 'DeploymentLogs'
$launcherPath = Join-Path $appDir 'Launcher-GISLabForm.ps1'
$legacyDir = 'C:\ProgramData\GISLab\FormBlocker'
$legacyLauncherPath = Join-Path $legacyDir 'Launcher-GISLabForm.ps1'
$surveyUrl = 'https://go.umd.edu/lib-GIS-lab'
$errors = [System.Collections.Generic.List[string]]::new()
$transcriptStarted = $false

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Error 'This script requires administrator or SYSTEM privileges.'
    exit 1
}

try {
    New-Item -ItemType Directory -Path $deploymentLogDir -Force | Out-Null
    Start-Transcript -Path (Join-Path $deploymentLogDir 'uninstall.log') -Append | Out-Null
    $transcriptStarted = $true
} catch {
    $errors.Add("Unable to start the uninstall log: $($_.Exception.Message)")
}

try {
    $launcherPatterns = @(
        [regex]::Escape($launcherPath)
        [regex]::Escape($legacyLauncherPath)
    )
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object {
            $commandLine = $_.CommandLine
            $launcherPatterns.Where({ $commandLine -match $_ }).Count -gt 0
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
} catch {
    $errors.Add("Failed to stop launcher processes: $($_.Exception.Message)")
}

try {
    $urlPattern = [regex]::Escape($surveyUrl)
    $profilePattern = [regex]::Escape('UMDLibraries\GISLabForm\EdgeProfile')
    Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
        Where-Object { $_.CommandLine -match $urlPattern -or $_.CommandLine -match $profilePattern } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
} catch {
    $errors.Add("Failed to stop GIS Lab Edge processes: $($_.Exception.Message)")
}

try {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
} catch {
    $errors.Add("Failed to remove scheduled task: $($_.Exception.Message)")
}

try {
    foreach ($directory in @($appDir, $legacyDir)) {
        if (Test-Path -LiteralPath $directory) {
            Remove-Item -LiteralPath $directory -Recurse -Force
        }
    }
} catch {
    $errors.Add("Failed to remove application files: $($_.Exception.Message)")
}

# Remove only this application's dedicated Edge data from local user profiles.
try {
    Get-ChildItem -LiteralPath 'C:\Users' -Directory -Force | ForEach-Object {
        $profileData = Join-Path $_.FullName 'AppData\Local\UMDLibraries\GISLabForm'
        if (Test-Path -LiteralPath $profileData) {
            Remove-Item -LiteralPath $profileData -Recurse -Force
        }
    }
} catch {
    $errors.Add("Failed to remove one or more Edge profile directories: $($_.Exception.Message)")
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "ERROR: $_" }
    Write-Host 'GIS Lab Check-In Helper uninstall failed or completed only partially.'
    $exitCode = 1
} else {
    Write-Host 'GIS Lab Check-In Helper uninstalled successfully.'
    $exitCode = 0
}

if ($transcriptStarted) {
    try { Stop-Transcript | Out-Null } catch {}
}
exit $exitCode
