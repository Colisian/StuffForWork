<#
.SYNOPSIS
    Harvests application launch counts and total runtime from the Windows
    Security log (Event IDs 4688 / 4689) into a durable per-machine CSV.

.DESCRIPTION
    Designed to run on a schedule (e.g. every 15 min) as SYSTEM on lab PCs.
    - Reads only NEW events since the last run (bookmark by RecordId).
    - Filters to a configurable watch list of executables.
    - Pairs ProcessStart (4688) with ProcessStop (4689) by ProcessId to
      compute per-launch duration.
    - Upserts a running tally: LaunchCount += 1, TotalSeconds += duration.
    - Output is machine-wide, in C:\ProgramData\LabUsage, surviving user logoff.

.NOTES
    Requires: "Process Creation" + "Process Termination" auditing enabled.
    Run context: SYSTEM (needs read access to the Security log).
    Author: UMD Libraries ITFO
#>

[CmdletBinding()]
param(
    # Executables to track. Match is case-insensitive on the leaf file name.
    [string[]]$WatchList = @(
        'chrome.exe','msedge.exe','firefox.exe',
        'WINWORD.EXE','EXCEL.EXE','POWERPNT.EXE','OUTLOOK.EXE',
        'Acrobat.exe','AcroRd32.exe', 'ArcGISPro.exe', 'ArcMap.exe', 'ArcCatalog.exe',
        'Code.exe','powershell.exe','pwsh.exe',
        'matlab.exe','Rgui.exe','python.exe'
    ),

    [string]$DataDir   = "$env:ProgramData\LabUsage",
    [string]$CsvPath   = "$env:ProgramData\LabUsage\usage.csv",
    [string]$StatePath = "$env:ProgramData\LabUsage\.bookmark.json"
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 0. Setup
# ---------------------------------------------------------------------------
if (-not (Test-Path $DataDir)) {
    New-Item -Path $DataDir -ItemType Directory -Force | Out-Null
}

# Transcript so SYSTEM-scheduled runs leave a trail on failure.
$logPath = Join-Path $DataDir 'harvest.log'
Start-Transcript -Path $logPath -Append -ErrorAction SilentlyContinue | Out-Null

# Normalize watch list to a fast lookup (lowercase leaf names)
$watch = @{}
foreach ($w in $WatchList) { $watch[$w.ToLowerInvariant()] = $true }

# ---------------------------------------------------------------------------
# 1. Determine where we left off (bookmark by max RecordId processed)
# ---------------------------------------------------------------------------
$lastRecordId = 0
if (Test-Path $StatePath) {
    try {
        $state = Get-Content $StatePath -Raw | ConvertFrom-Json
        if ($state.LastRecordId) { $lastRecordId = [int64]$state.LastRecordId }
    } catch {
        Write-Warning "Bookmark unreadable, starting fresh: $_"
    }
}

# ---------------------------------------------------------------------------
# 2. Pull new 4688 (start) and 4689 (stop) events from the Security log
# ---------------------------------------------------------------------------
# Push both the event-ID and RecordID filter into the XPath query so we don't
# materialize the entire Security log every run.
$xpath = "*[System[(EventID=4688 or EventID=4689) and (EventRecordID > $lastRecordId)]]"

try {
    $events = Get-WinEvent -LogName Security -FilterXPath $xpath -ErrorAction Stop |
              Sort-Object RecordId
} catch {
    if ($_.Exception.Message -match 'No events were found') {
        $events = @()
    } else {
        Write-Error "Failed to read Security log: $_"
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 1
    }
}

if (-not $events -or $events.Count -eq 0) {
    Write-Verbose "No new events since RecordId $lastRecordId."
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    exit 0
}

$maxRecordId = ($events | Measure-Object RecordId -Maximum).Maximum

# ---------------------------------------------------------------------------
# 3. Parse events. Track open processes (started, awaiting stop) across runs.
# ---------------------------------------------------------------------------
# Open-process state persists between runs so a launch in one window and an
# exit in the next still produce a correct duration.
$openPath = Join-Path $DataDir ".open.json"
$open = @{}   # key: "ProcessId|exe"  value: start DateTime (ticks)
if (Test-Path $openPath) {
    try {
        (Get-Content $openPath -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $open[$_.Name] = [int64]$_.Value }
    } catch { }
}

# Accumulators for this batch:  exe -> @{ Launches; Seconds }
$batch = @{}
function Add-Stat([string]$exe,[int]$launches,[double]$seconds) {
    if (-not $batch.ContainsKey($exe)) {
        $batch[$exe] = [pscustomobject]@{ Launches = 0; Seconds = 0.0 }
    }
    $batch[$exe].Launches += $launches
    $batch[$exe].Seconds  += $seconds
}

foreach ($e in $events) {
    $xml = [xml]$e.ToXml()
    $data = @{}
    foreach ($d in $xml.Event.EventData.Data) { $data[$d.Name] = $d.'#text' }

    if ($e.Id -eq 4688) {
        # Process start
        $exePath = $data['NewProcessName']
        if (-not $exePath) { continue }
        $leaf = ([System.IO.Path]::GetFileName($exePath)).ToLowerInvariant()
        if (-not $watch.ContainsKey($leaf)) { continue }

        $pidHex = $data['NewProcessId']            # e.g. "0x1a2b"
        $pidDec = [Convert]::ToInt64($pidHex, 16)
        $key    = "$pidDec|$leaf"

        # Count the launch immediately (duration added at stop)
        Add-Stat $leaf 1 0
        $open[$key] = $e.TimeCreated.Ticks
    }
    elseif ($e.Id -eq 4689) {
        # Process stop
        $exePath = $data['ProcessName']
        if (-not $exePath) { continue }
        $leaf = ([System.IO.Path]::GetFileName($exePath)).ToLowerInvariant()
        if (-not $watch.ContainsKey($leaf)) { continue }

        $pidHex = $data['ProcessId']
        $pidDec = [Convert]::ToInt64($pidHex, 16)
        $key    = "$pidDec|$leaf"

        if ($open.ContainsKey($key)) {
            $startTicks = $open[$key]
            $dur = ($e.TimeCreated.Ticks - $startTicks) / 1e7   # ticks -> sec
            if ($dur -ge 0) { Add-Stat $leaf 0 $dur }
            $open.Remove($key)
        }
        # else: stop with no matching start in our window -> ignore duration
    }
}

# ---------------------------------------------------------------------------
# 3b. Credit still-running processes with elapsed time so long GIS sessions
#     (ArcGIS Pro left open all day, etc.) actually show up in TotalSeconds
#     instead of counting only at process exit.
# ---------------------------------------------------------------------------
$creditPath = Join-Path $DataDir '.credited.json'
$credited = @{}
if (Test-Path $creditPath) {
    try {
        (Get-Content $creditPath -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $credited[$_.Name] = [int64]$_.Value }
    } catch { }
}

$nowTicks = (Get-Date).Ticks
foreach ($k in @($open.Keys)) {
    $leaf     = ($k -split '\|', 2)[1]
    $lastMark = if ($credited.ContainsKey($k)) { $credited[$k] } else { $open[$k] }
    $delta    = ($nowTicks - $lastMark) / 1e7
    if ($delta -gt 0) { Add-Stat $leaf 0 $delta }
    $credited[$k] = $nowTicks
}
# Drop credit entries for processes that have since exited.
foreach ($k in @($credited.Keys)) {
    if (-not $open.ContainsKey($k)) { $credited.Remove($k) }
}

# ---------------------------------------------------------------------------
# 4. Load existing CSV, merge batch totals, write back
# ---------------------------------------------------------------------------
$rows = @{}
if (Test-Path $CsvPath) {
    Import-Csv $CsvPath | ForEach-Object {
        $rows[$_.Application] = [pscustomobject]@{
            Application  = $_.Application
            LaunchCount  = [int64]$_.LaunchCount
            TotalSeconds = [double]$_.TotalSeconds
            TotalHours   = 0.0
            LastUpdated  = $_.LastUpdated
        }
    }
}

$now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
foreach ($exe in $batch.Keys) {
    if (-not $rows.ContainsKey($exe)) {
        $rows[$exe] = [pscustomobject]@{
            Application  = $exe
            LaunchCount  = 0
            TotalSeconds = 0.0
            TotalHours   = 0.0
            LastUpdated  = $now
        }
    }
    $rows[$exe].LaunchCount  += $batch[$exe].Launches
    $rows[$exe].TotalSeconds += $batch[$exe].Seconds
    $rows[$exe].LastUpdated   = $now
}

# Recompute hours and emit, sorted by most-used
$out = $rows.Values | ForEach-Object {
    $_.TotalSeconds = [math]::Round($_.TotalSeconds, 1)
    $_.TotalHours   = [math]::Round($_.TotalSeconds / 3600, 2)
    $_
} | Sort-Object TotalSeconds -Descending

# Write CSV via temp file + Move-Item so a partial write can't corrupt the
# existing file. If write fails (e.g. Excel has usage.csv open), bail without
# advancing the bookmark so the same events get retried next run.
$tmp = "$CsvPath.tmp"
try {
    $out | Export-Csv -Path $tmp -NoTypeInformation -Encoding UTF8
    Move-Item -Path $tmp -Destination $CsvPath -Force
} catch {
    Write-Error "CSV write failed, not advancing bookmark: $_"
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    exit 1
}

# ---------------------------------------------------------------------------
# 5. Persist state (bookmark + still-open processes + credit marks)
#    Only reached on successful CSV write above.
# ---------------------------------------------------------------------------
@{ LastRecordId = $maxRecordId; UpdatedAt = $now } |
    ConvertTo-Json | Set-Content $StatePath -Encoding UTF8

# Prune very old open entries (>24h) so a missed 4689 doesn't leak forever
$cutoff = (Get-Date).AddHours(-24).Ticks
$openClean = @{}
foreach ($k in $open.Keys) { if ($open[$k] -ge $cutoff) { $openClean[$k] = $open[$k] } }
($openClean | ConvertTo-Json) | Set-Content $openPath -Encoding UTF8

# Persist credit marks aligned with the pruned open set.
$creditClean = @{}
foreach ($k in $credited.Keys) { if ($openClean.ContainsKey($k)) { $creditClean[$k] = $credited[$k] } }
($creditClean | ConvertTo-Json) | Set-Content $creditPath -Encoding UTF8

Write-Verbose "Processed $($events.Count) events up to RecordId $maxRecordId."
Stop-Transcript -ErrorAction SilentlyContinue | Out-Null