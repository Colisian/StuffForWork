#Requires -Version 5.1

<#
.SYNOPSIS
    Aggregates selected application launches and runtime from events 4688/4689.

.DESCRIPTION
    Runs as SYSTEM on a schedule. A single atomic state file is the source of
    truth; usage.csv is a replaceable report generated from that state. Open
    processes are credited only while the same PID and process start time are
    present during the current Windows boot.

.NOTES
    Author: UMD Libraries ITFO
    Date: 2026-09-07
    Version: 2.0.0
    Requires successful Process Creation and Process Termination auditing.
#>

[CmdletBinding()]
param(
    [string[]]$WatchList,
    [string]$WatchListPath,
    [string]$DataDir = "$env:ProgramData\LabUsage",
    [string]$CsvPath,
    [string]$StatePath,
    [ValidateRange(1, 168)]
    [int]$StaleProcessHours = 24
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    $CsvPath = Join-Path $DataDir 'usage.csv'
}
if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = Join-Path $DataDir 'state.json'
}
function Write-AtomicFile {
    <#
    .SYNOPSIS
        Writes content to a same-directory temporary file and atomically swaps it.
    .NOTES
        Author: UMD Libraries ITFO; Date: 2026-09-07; Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Content
    )

    $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $backupPath = "$Path.previous"
    try {
        Set-Content -LiteralPath $temporaryPath -Value $Content -Encoding UTF8
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            [System.IO.File]::Replace($temporaryPath, $Path, $backupPath)
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        } else {
            Move-Item -LiteralPath $temporaryPath -Destination $Path
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-BootUtcTicks {
    <#
    .SYNOPSIS
        Returns the current operating-system boot time as UTC ticks.
    .NOTES
        Author: UMD Libraries ITFO; Date: 2026-09-07; Version: 2.0.0
    #>
    [CmdletBinding()]
    param()

    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
    return [int64]$operatingSystem.LastBootUpTime.ToUniversalTime().Ticks
}

function ConvertFrom-LegacyLocalTicks {
    <#
    .SYNOPSIS
        Converts version 1 local DateTime ticks to version 2 UTC ticks.
    .NOTES
        Author: UMD Libraries ITFO; Date: 2026-09-07; Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int64]$Ticks
    )

    $legacyTime = [datetime]::SpecifyKind([datetime]$Ticks, [DateTimeKind]::Local)
    return [int64]$legacyTime.ToUniversalTime().Ticks
}

function Test-TrackedProcess {
    <#
    .SYNOPSIS
        Confirms that a saved PID still represents the original executable.
    .NOTES
        Author: UMD Libraries ITFO; Date: 2026-09-07; Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        [Parameter(Mandatory)]
        [psobject]$Record
    )

    $parts = $Key -split '\|', 2
    if ($parts.Count -ne 2) { return $false }
    $processId = [int64]$parts[0]
    $expectedLeaf = $parts[1]
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if (-not $process) { return $false }
    if (("$($process.ProcessName).exe") -ine $expectedLeaf) { return $false }

    try {
        $actualStart = [int64]$process.StartTime.ToUniversalTime().Ticks
        $difference = [math]::Abs($actualStart - [int64]$Record.StartUtcTicks) / 1e7
        return ($difference -le 5)
    } catch {
        # SYSTEM can normally read StartTime. If a protected process blocks it,
        # matching PID and executable name is the safest available fallback.
        return $true
    }
}

function Add-UsageStat {
    <#
    .SYNOPSIS
        Adds launch and runtime values to this run's accumulator.
    .NOTES
        Author: UMD Libraries ITFO; Date: 2026-09-07; Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Application,
        [int64]$Launches = 0,
        [double]$Seconds = 0
    )

    if (-not $script:batch.ContainsKey($Application)) {
        $script:batch[$Application] = [pscustomobject]@{ Launches = 0L; Seconds = 0.0 }
    }
    $script:batch[$Application].Launches += $Launches
    $script:batch[$Application].Seconds += $Seconds
}

if (-not (Test-Path -LiteralPath $DataDir)) {
    New-Item -Path $DataDir -ItemType Directory -Force | Out-Null
}
$logDir = "$env:ProgramData\UMDLibraries\AppUsage"
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}
$logPath = Join-Path $logDir 'AppUsageTracking-Harvest.log'
if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 1MB) {
    Move-Item -LiteralPath $logPath -Destination "$logPath.old" -Force -ErrorAction SilentlyContinue
}
Start-Transcript -Path $logPath -Append -ErrorAction SilentlyContinue | Out-Null

try {
    if (-not $WatchList -or $WatchList.Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($WatchListPath)) {
            $WatchListPath = Join-Path $DataDir 'AppUsageTracking-WatchList.txt'
        }
        if (-not (Test-Path -LiteralPath $WatchListPath -PathType Leaf)) {
            throw "Watch list not found: $WatchListPath"
        }
        $WatchList = @(Get-Content -LiteralPath $WatchListPath | Where-Object {
            $_ -and $_.Trim() -and -not $_.Trim().StartsWith('#')
        } | ForEach-Object { $_.Trim() })
    }
    if ($WatchList.Count -eq 0) { throw 'The application watch list is empty.' }

    $watch = @{}
    foreach ($item in $WatchList) {
        $leaf = [System.IO.Path]::GetFileName($item).ToLowerInvariant()
        if ($leaf) { $watch[$leaf] = $true }
    }

    $currentBootTicks = Get-BootUtcTicks
    $lastRecordId = -1L
    $open = @{}
    $rows = @{}
    $loadedVersion2State = $false

    if (Test-Path -LiteralPath $StatePath) {
        try {
            $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
            if ([int]$state.SchemaVersion -ne 2) {
                throw "Unsupported state schema: $($state.SchemaVersion)"
            }
            $lastRecordId = [int64]$state.LastRecordId
            foreach ($entry in @($state.OpenProcesses)) {
                if ($null -eq $entry -or -not $entry.Key) { continue }
                $open[[string]$entry.Key] = [pscustomobject]@{
                    StartUtcTicks = [int64]$entry.StartUtcTicks
                    CreditedUtcTicks = [int64]$entry.CreditedUtcTicks
                    BootUtcTicks = [int64]$entry.BootUtcTicks
                }
            }
            foreach ($row in @($state.Totals)) {
                if ($null -eq $row -or -not $row.Application) { continue }
                $application = ([string]$row.Application).ToLowerInvariant()
                $rows[$application] = [pscustomobject]@{
                    Application = $application
                    LaunchCount = [int64]$row.LaunchCount
                    TotalSeconds = [double]$row.TotalSeconds
                    LastUpdated = [string]$row.LastUpdated
                }
            }
            $loadedVersion2State = $true
        } catch {
            throw "State file is unreadable; refusing to risk duplicate counts: $StatePath. $_"
        }
    }

    # One-time migration from the original three state files and CSV.
    if (-not $loadedVersion2State) {
        $legacyBookmark = Join-Path $DataDir '.bookmark.json'
        $legacyOpen = Join-Path $DataDir '.open.json'
        $legacyCredited = Join-Path $DataDir '.credited.json'
        $legacyCredits = @{}

        if (Test-Path -LiteralPath $legacyBookmark) {
            $bookmark = Get-Content -LiteralPath $legacyBookmark -Raw | ConvertFrom-Json
            $lastRecordId = [int64]$bookmark.LastRecordId
        }
        if (Test-Path -LiteralPath $CsvPath) {
            Import-Csv -LiteralPath $CsvPath | ForEach-Object {
                $application = ([string]$_.Application).ToLowerInvariant()
                $rows[$application] = [pscustomobject]@{
                    Application = $application
                    LaunchCount = [int64]$_.LaunchCount
                    TotalSeconds = [double]$_.TotalSeconds
                    LastUpdated = [string]$_.LastUpdated
                }
            }
        }
        if (Test-Path -LiteralPath $legacyCredited) {
            $creditObject = Get-Content -LiteralPath $legacyCredited -Raw | ConvertFrom-Json
            $creditObject.PSObject.Properties | ForEach-Object {
                $legacyCredits[$_.Name] = ConvertFrom-LegacyLocalTicks -Ticks ([int64]$_.Value)
            }
        }
        if (Test-Path -LiteralPath $legacyOpen) {
            $openObject = Get-Content -LiteralPath $legacyOpen -Raw | ConvertFrom-Json
            $openObject.PSObject.Properties | ForEach-Object {
                $startTicks = ConvertFrom-LegacyLocalTicks -Ticks ([int64]$_.Value)
                $creditedTicks = if ($legacyCredits.ContainsKey($_.Name)) {
                    $legacyCredits[$_.Name]
                } else {
                    $startTicks
                }
                $open[$_.Name] = [pscustomobject]@{
                    StartUtcTicks = $startTicks
                    CreditedUtcTicks = $creditedTicks
                    BootUtcTicks = if ($startTicks -ge $currentBootTicks) { $currentBootTicks } else { 0L }
                }
            }
        }
    }

    $newest = Get-WinEvent -LogName Security -MaxEvents 1 -ErrorAction SilentlyContinue
    $newestRecordId = if ($newest) { [int64]$newest.RecordId } else { 0L }
    if ($lastRecordId -lt 0) {
        $lastRecordId = $newestRecordId
        Write-Warning "No bookmark found; harvesting starts at RecordId $lastRecordId."
    } elseif ($newestRecordId -lt $lastRecordId) {
        Write-Warning 'The Security log was cleared; restarting event collection at RecordId 0.'
        $lastRecordId = 0L
    }

    $xpath = "*[System[(EventID=4688 or EventID=4689) and (EventRecordID > $lastRecordId)]]"
    try {
        $events = @(Get-WinEvent -LogName Security -FilterXPath $xpath -ErrorAction Stop |
            Sort-Object RecordId)
    } catch {
        if ($_.CategoryInfo.Category -eq 'ObjectNotFound' -or
            $_.Exception.Message -match 'No events were found') {
            $events = @()
        } else {
            throw "Failed to read the Security log: $_"
        }
    }

    $maxRecordId = $lastRecordId
    if ($events.Count -gt 0) {
        $maxRecordId = [int64]($events | Measure-Object RecordId -Maximum).Maximum
    }
    $script:batch = @{}

    foreach ($event in $events) {
        try {
            $xml = [xml]$event.ToXml()
            $eventData = @{}
            foreach ($item in $xml.Event.EventData.Data) { $eventData[$item.Name] = $item.'#text' }

            if ($event.Id -eq 4688) {
                $executablePath = $eventData['NewProcessName']
                if (-not $executablePath) { continue }
                $leaf = [System.IO.Path]::GetFileName($executablePath).ToLowerInvariant()
                if (-not $watch.ContainsKey($leaf)) { continue }
                if ($eventData['SubjectUserSid'] -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) { continue }

                $processId = [Convert]::ToInt64($eventData['NewProcessId'], 16)
                $key = "$processId|$leaf"
                $startTicks = [int64]$event.TimeCreated.ToUniversalTime().Ticks
                Add-UsageStat -Application $leaf -Launches 1
                $open[$key] = [pscustomobject]@{
                    StartUtcTicks = $startTicks
                    CreditedUtcTicks = $startTicks
                    BootUtcTicks = $currentBootTicks
                }
            } elseif ($event.Id -eq 4689) {
                $executablePath = $eventData['ProcessName']
                if (-not $executablePath) { continue }
                $leaf = [System.IO.Path]::GetFileName($executablePath).ToLowerInvariant()
                if (-not $watch.ContainsKey($leaf)) { continue }

                $processId = [Convert]::ToInt64($eventData['ProcessId'], 16)
                $key = "$processId|$leaf"
                if ($open.ContainsKey($key)) {
                    $stopTicks = [int64]$event.TimeCreated.ToUniversalTime().Ticks
                    $baseTicks = [math]::Max(
                        [int64]$open[$key].StartUtcTicks,
                        [int64]$open[$key].CreditedUtcTicks
                    )
                    $duration = ($stopTicks - $baseTicks) / 1e7
                    if ($duration -gt 0) {
                        Add-UsageStat -Application $leaf -Seconds $duration
                    }
                    $open.Remove($key)
                }
            }
        } catch {
            Write-Warning "Skipping malformed event RecordId $($event.RecordId): $_"
        }
    }

    # Credit only a live instance from this boot. Inactive entries remain for
    # one grace window so a delayed 4689 can supply the exact stop time.
    $nowUtcTicks = [int64](Get-Date).ToUniversalTime().Ticks
    $staleTicks = [int64](New-TimeSpan -Hours $StaleProcessHours).Ticks
    foreach ($key in @($open.Keys)) {
        $record = $open[$key]
        if ([int64]$record.BootUtcTicks -ne $currentBootTicks -or
            [int64]$record.StartUtcTicks -lt $currentBootTicks) {
            $open.Remove($key)
            continue
        }

        if (Test-TrackedProcess -Key $key -Record $record) {
            $lastCredit = [math]::Max(
                [int64]$record.StartUtcTicks,
                [int64]$record.CreditedUtcTicks
            )
            $duration = ($nowUtcTicks - $lastCredit) / 1e7
            if ($duration -gt 0) {
                $leaf = ($key -split '\|', 2)[1]
                Add-UsageStat -Application $leaf -Seconds $duration
                $record.CreditedUtcTicks = $nowUtcTicks
            }
        } elseif (($nowUtcTicks - [int64]$record.CreditedUtcTicks) -gt $staleTicks) {
            $open.Remove($key)
        }
    }

    $updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    foreach ($application in $script:batch.Keys) {
        if (-not $rows.ContainsKey($application)) {
            $rows[$application] = [pscustomobject]@{
                Application = $application
                LaunchCount = 0L
                TotalSeconds = 0.0
                LastUpdated = $updated
            }
        }
        $rows[$application].LaunchCount += $script:batch[$application].Launches
        $rows[$application].TotalSeconds += $script:batch[$application].Seconds
        $rows[$application].LastUpdated = $updated
    }

    $stateTotals = @($rows.Values | Sort-Object Application | ForEach-Object {
        [pscustomobject]@{
            Application = $_.Application
            LaunchCount = [int64]$_.LaunchCount
            TotalSeconds = [math]::Round([double]$_.TotalSeconds, 3)
            LastUpdated = $_.LastUpdated
        }
    })
    $stateOpen = @($open.Keys | Sort-Object | ForEach-Object {
        [pscustomobject]@{
            Key = $_
            StartUtcTicks = [int64]$open[$_].StartUtcTicks
            CreditedUtcTicks = [int64]$open[$_].CreditedUtcTicks
            BootUtcTicks = [int64]$open[$_].BootUtcTicks
        }
    })
    $newState = [ordered]@{
        SchemaVersion = 2
        LastRecordId = $maxRecordId
        UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        OpenProcesses = $stateOpen
        Totals = $stateTotals
    }

    # Commit source-of-truth state first. If report replacement fails, the next
    # run regenerates it without replaying or duplicating committed events.
    $stateJson = $newState | ConvertTo-Json -Depth 6
    Write-AtomicFile -Path $StatePath -Content $stateJson

    $report = @($stateTotals | ForEach-Object {
        [pscustomobject]@{
            Application = $_.Application
            LaunchCount = $_.LaunchCount
            TotalSeconds = [math]::Round($_.TotalSeconds, 1)
            TotalHours = [math]::Round($_.TotalSeconds / 3600, 2)
            LastUpdated = $_.LastUpdated
        }
    } | Sort-Object TotalSeconds -Descending)
    $csvContent = @($report | ConvertTo-Csv -NoTypeInformation)
    if ($csvContent.Count -eq 0) {
        $csvContent = '"Application","LaunchCount","TotalSeconds","TotalHours","LastUpdated"'
    }
    Write-AtomicFile -Path $CsvPath -Content $csvContent

    # Migration cleanup happens only after both version 2 outputs are durable.
    @('.bookmark.json', '.open.json', '.credited.json') | ForEach-Object {
        $legacyPath = Join-Path $DataDir $_
        Remove-Item -LiteralPath $legacyPath -Force -ErrorAction SilentlyContinue
    }

    Write-Verbose "Processed $($events.Count) events through RecordId $maxRecordId."
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
