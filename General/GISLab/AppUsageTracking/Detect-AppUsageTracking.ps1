#Requires -Version 5.1

<#
.SYNOPSIS
    Intune custom detection for GIS Lab application-usage tracking.

.NOTES
    Author: UMD Libraries ITFO
    Date: 2026-09-07
    Version: 2.0.0
    Intune detection contract: exit 0 with output when compliant; exit 1 otherwise.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$requiredVersion = [version]'2.0.0'
$registryPath = 'HKLM:\SOFTWARE\UMDLibraries\LabAppUsageTracking'

try {
    $sentinel = Get-ItemProperty -Path $registryPath -ErrorAction Stop
    if ([int]$sentinel.Installed -ne 1) { throw 'Installation sentinel is incomplete.' }
    if ([version]$sentinel.Version -lt $requiredVersion) { throw 'Installed version is outdated.' }

    $installDir = [string]$sentinel.InstallDir
    $taskName = [string]$sentinel.TaskName
    $intervalMinutes = [int]$sentinel.IntervalMinutes
    $harvester = Join-Path $installDir 'Harvest-AppUsage.ps1'
    $watchList = Join-Path $installDir 'AppUsageTracking-WatchList.txt'
    $statePath = Join-Path $installDir 'state.json'
    $csvPath = Join-Path $installDir 'usage.csv'
    if (-not (Test-Path -LiteralPath $harvester -PathType Leaf) -or
        -not (Test-Path -LiteralPath $watchList -PathType Leaf) -or
        -not (Test-Path -LiteralPath $statePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
        throw 'One or more required deployment files are missing.'
    }

    $actualHash = (Get-FileHash -LiteralPath $harvester -Algorithm SHA256).Hash
    if ($actualHash -ine [string]$sentinel.HarvesterSha256) {
        throw 'The deployed harvester does not match the installed version.'
    }
    $actualWatchListHash = (Get-FileHash -LiteralPath $watchList -Algorithm SHA256).Hash
    if ($actualWatchListHash -ine [string]$sentinel.WatchListSha256) {
        throw 'The deployed watch list does not match the installed version.'
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ([int]$state.SchemaVersion -ne 2) { throw 'The state schema is invalid.' }

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    $expectedPowerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $expectedFileArgument = "-File `"$harvester`""
    $expectedDataArgument = "-DataDir `"$installDir`""
    $expectedWatchListArgument = "-WatchListPath `"$watchList`""
    $validAction = @($task.Actions | Where-Object {
        $_.Execute -ieq $expectedPowerShell -and
        $_.Arguments -like "*$expectedFileArgument*" -and
        $_.Arguments -like "*$expectedDataArgument*" -and
        $_.Arguments -like "*$expectedWatchListArgument*"
    }).Count -gt 0
    if (-not $validAction) { throw 'The scheduled-task action is incorrect.' }
    if ($task.Principal.UserId -notin @('SYSTEM', 'NT AUTHORITY\SYSTEM', 'S-1-5-18')) {
        throw 'The scheduled task is not configured to run as SYSTEM.'
    }

    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
    if ($taskInfo.LastTaskResult -notin @(0, 267009)) {
        throw "The scheduled task returned $($taskInfo.LastTaskResult)."
    }
    $maximumAge = [math]::Max(($intervalMinutes * 3) + 5, 50)
    if ($taskInfo.LastRunTime -lt (Get-Date).AddMinutes(-$maximumAge)) {
        throw 'The scheduled task has not run recently.'
    }

    # Recent real events validate effective auditing without parsing localized
    # auditpol output. Setup creates a test pair, and each task run creates a
    # subsequent PowerShell process pair.
    $recentEvents = @(Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        Id = 4688, 4689
        StartTime = (Get-Date).AddMinutes(-$maximumAge)
    } -MaxEvents 500 -ErrorAction Stop)
    if (4688 -notin $recentEvents.Id -or 4689 -notin $recentEvents.Id) {
        throw 'Recent process-audit events were not found.'
    }

    Write-Output "Compliant: App usage tracking $($sentinel.Version)"
    exit 0
} catch {
    Write-Output "Not compliant: $($_.Exception.Message)"
    exit 1
}
