#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs and validates the GIS Lab application-usage harvester.

.DESCRIPTION
    Enables process auditing, secures the data directory, deploys the
    harvester, registers its SYSTEM scheduled task, performs a test run, and
    writes a registry detection sentinel only after validation succeeds.

.NOTES
    Author: UMD Libraries ITFO
    Date: 2026-09-07
    Version: 2.0.0
    Run as Administrator or as SYSTEM through Intune.
#>

[CmdletBinding()]
param(
    [string]$ScriptSource,
    [string]$ConfigSource,
    [string]$InstallDir = "$env:ProgramData\LabUsage",
    [ValidateRange(5, 1440)]
    [int]$IntervalMin = 15,
    [switch]$IncludeCmdLine
)

$ErrorActionPreference = 'Stop'
$scriptVersion = '2.0.0'
$taskName = 'LabAppUsageHarvester'
$registryPath = 'HKLM:\SOFTWARE\UMDLibraries\LabAppUsageTracking'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($ScriptSource)) {
    $ScriptSource = Join-Path $scriptDir 'Harvest-AppUsage.ps1'
}
if ([string]::IsNullOrWhiteSpace($ConfigSource)) {
    $ConfigSource = Join-Path $scriptDir 'AppUsageTracking-WatchList.txt'
}

$deploymentLogDir = "$env:ProgramData\UMDLibraries\AppUsage"
if (-not (Test-Path -LiteralPath $deploymentLogDir)) {
    New-Item -Path $deploymentLogDir -ItemType Directory -Force | Out-Null
}
$setupLog = Join-Path $deploymentLogDir 'AppUsageTracking-Setup.log'
Start-Transcript -Path $setupLog -Append -ErrorAction SilentlyContinue | Out-Null

function Test-ProcessAuditEvents {
    <#
    .SYNOPSIS
        Generates and verifies one process-creation and termination audit pair.
    .NOTES
        Author: UMD Libraries ITFO; Date: 2026-09-07; Version: 2.0.0
    #>
    [CmdletBinding()]
    param()

    $newest = Get-WinEvent -LogName Security -MaxEvents 1 -ErrorAction SilentlyContinue
    $baseline = if ($newest) { [int64]$newest.RecordId } else { 0 }
    $testProcess = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" `
        -ArgumentList '/d /c exit 0' -Wait -PassThru -WindowStyle Hidden
    $foundStart = $false
    $foundStop = $false
    $xpath = "*[System[(EventID=4688 or EventID=4689) and (EventRecordID > $baseline)]]"

    for ($attempt = 1; $attempt -le 15 -and -not ($foundStart -and $foundStop); $attempt++) {
        Start-Sleep -Seconds 1
        $auditEvents = @(Get-WinEvent -LogName Security -FilterXPath $xpath -ErrorAction SilentlyContinue)
        foreach ($auditEvent in $auditEvents) {
            $xml = [xml]$auditEvent.ToXml()
            $eventData = @{}
            foreach ($item in $xml.Event.EventData.Data) { $eventData[$item.Name] = $item.'#text' }
            $eventPid = if ($auditEvent.Id -eq 4688) {
                $eventData['NewProcessId']
            } else {
                $eventData['ProcessId']
            }
            if (-not $eventPid) { continue }
            if ([Convert]::ToInt64($eventPid, 16) -ne $testProcess.Id) { continue }
            if ($auditEvent.Id -eq 4688) { $foundStart = $true }
            if ($auditEvent.Id -eq 4689) { $foundStop = $true }
        }
    }

    return ($foundStart -and $foundStop)
}

if (-not (Test-Path -LiteralPath $ScriptSource -PathType Leaf)) {
    throw "Harvester source not found: $ScriptSource"
}
if (-not (Test-Path -LiteralPath $ConfigSource -PathType Leaf)) {
    throw "Watch-list source not found: $ConfigSource"
}

# Secure the data directory before installing executable content into it.
if (-not (Test-Path -LiteralPath $InstallDir)) {
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
}
$acl = Get-Acl -LiteralPath $InstallDir
$acl.SetAccessRuleProtection($true, $false)
$sidSystem = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-18'
$sidAdmins = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'
$sidUsers = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-545'
$rules = @(
    New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidSystem, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidAdmins, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidUsers, 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
)
@($acl.Access) | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
$rules | ForEach-Object { $acl.AddAccessRule($_) }
Set-Acl -LiteralPath $InstallDir -AclObject $acl

try {
    # Stop an existing instance before replacing files or migrating state.
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask -and $existingTask.State -eq 'Running') {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop
        $stopDeadline = (Get-Date).AddSeconds(15)
        do {
            Start-Sleep -Milliseconds 500
            $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        } while ($existingTask -and $existingTask.State -eq 'Running' -and
            (Get-Date) -lt $stopDeadline)
        if ($existingTask -and $existingTask.State -eq 'Running') {
            throw "Existing scheduled task '$taskName' did not stop within 15 seconds."
        }
    }

    $harvest = Join-Path $InstallDir 'Harvest-AppUsage.ps1'
    $watchListPath = Join-Path $InstallDir 'AppUsageTracking-WatchList.txt'
    Copy-Item -LiteralPath $ScriptSource -Destination $harvest -Force
    Copy-Item -LiteralPath $ConfigSource -Destination $watchListPath -Force

    # GUIDs avoid localized audit-policy category names.
    $auditGuids = @(
        '{0CCE922B-69AE-11D9-BED3-505054503030}', # Process Creation
        '{0CCE922C-69AE-11D9-BED3-505054503030}'  # Process Termination
    )
    foreach ($auditGuid in $auditGuids) {
        & auditpol.exe /set "/subcategory:$auditGuid" /success:enable | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "auditpol failed for subcategory $auditGuid with exit code $LASTEXITCODE."
        }
    }
    if (-not (Test-ProcessAuditEvents)) {
        throw 'Process audit validation failed: the generated 4688/4689 test events were not found.'
    }

    if ($IncludeCmdLine) {
        $auditRegistry = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
        New-Item -Path $auditRegistry -Force | Out-Null
        Set-ItemProperty -Path $auditRegistry -Name 'ProcessCreationIncludeCmdLine_Enabled' `
            -Value 1 -Type DWord -Force
    }

    # Seed only a genuinely new deployment. Existing v1 files are migrated by
    # the harvester so upgrades retain their counts and process state.
    $statePath = Join-Path $InstallDir 'state.json'
    $legacyBookmark = Join-Path $InstallDir '.bookmark.json'
    $csvPath = Join-Path $InstallDir 'usage.csv'
    if (-not (Test-Path $statePath) -and -not (Test-Path $legacyBookmark) -and
        -not (Test-Path $csvPath)) {
        $newest = Get-WinEvent -LogName Security -MaxEvents 1 -ErrorAction SilentlyContinue
        $seed = if ($newest) { [int64]$newest.RecordId } else { 0 }
        $initialState = [ordered]@{
            SchemaVersion = 2
            LastRecordId = $seed
            UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
            OpenProcesses = @()
            Totals = @()
        }
        $initialStateTemp = "$statePath.$([guid]::NewGuid().ToString('N')).tmp"
        try {
            $initialState | ConvertTo-Json -Depth 6 |
                Set-Content -LiteralPath $initialStateTemp -Encoding UTF8
            Move-Item -LiteralPath $initialStateTemp -Destination $statePath
        } finally {
            Remove-Item -LiteralPath $initialStateTemp -Force -ErrorAction SilentlyContinue
        }
    }

    $powerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $powerShellExe -PathType Leaf)) {
        throw "Windows PowerShell was not found at $powerShellExe."
    }
    $arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$harvest`" -DataDir `"$InstallDir`" -WatchListPath `"$watchListPath`""
    $action = New-ScheduledTaskAction -Execute $powerShellExe -Argument $arguments
    $trigger = @(
        New-ScheduledTaskTrigger -AtStartup
        New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
            -RepetitionInterval (New-TimeSpan -Minutes $IntervalMin) `
            -RepetitionDuration (New-TimeSpan -Days 3650)
    )
    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' `
        -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null

    # A successful SYSTEM run is required before Intune receives its sentinel.
    $validationStart = Get-Date
    Start-ScheduledTask -TaskName $taskName
    do {
        Start-Sleep -Seconds 1
        $task = Get-ScheduledTask -TaskName $taskName
    } while ($task.State -eq 'Running' -and (Get-Date) -lt $validationStart.AddSeconds(30))
    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
    if ($task.State -eq 'Running' -or $taskInfo.LastRunTime -lt $validationStart.AddSeconds(-1) -or
        $taskInfo.LastTaskResult -ne 0) {
        throw "Scheduled-task validation failed (state=$($task.State), result=$($taskInfo.LastTaskResult))."
    }
    if (-not (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
        throw "Scheduled-task validation failed: $csvPath was not created."
    }

    $hash = (Get-FileHash -LiteralPath $harvest -Algorithm SHA256).Hash
    $watchListHash = (Get-FileHash -LiteralPath $watchListPath -Algorithm SHA256).Hash
    New-Item -Path $registryPath -Force | Out-Null
    Set-ItemProperty -Path $registryPath -Name 'Installed' -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $registryPath -Name 'Version' -Value $scriptVersion -Type String -Force
    Set-ItemProperty -Path $registryPath -Name 'InstallDir' -Value $InstallDir -Type String -Force
    Set-ItemProperty -Path $registryPath -Name 'TaskName' -Value $taskName -Type String -Force
    Set-ItemProperty -Path $registryPath -Name 'IntervalMinutes' -Value $IntervalMin -Type DWord -Force
    Set-ItemProperty -Path $registryPath -Name 'HarvesterSha256' -Value $hash -Type String -Force
    Set-ItemProperty -Path $registryPath -Name 'WatchListSha256' -Value $watchListHash -Type String -Force
    Set-ItemProperty -Path $registryPath -Name 'InstalledUtc' `
        -Value (Get-Date).ToUniversalTime().ToString('o') -Type String -Force

    Write-Host "[+] App usage tracking $scriptVersion installed and validated."
    Write-Host "[+] Scheduled task: $taskName (every $IntervalMin minutes)"
    Write-Host "[+] CSV: $csvPath"
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
