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

# ---------------------------------------------------------------------------
# 0. Setup
# ---------------------------------------------------------------------------
if (-not (Test-Path $DataDir)) {
    New-Item -Path $DataDir -ItemType Directory -Force | Out-Null
}

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
$filter = @{ LogName = 'Security'; Id = 4688, 4689 }

try {
    $events = Get-WinEvent -FilterHashtable $filter -ErrorAction Stop |
              Where-Object { $_.RecordId -gt $lastRecordId } |
              Sort-Object RecordId
} catch {
    if ($_.Exception.Message -match 'No events were found') {
        $events = @()
    } else {
        Write-Error "Failed to read Security log: $_"
        exit 1
    }
}

if (-not $events -or $events.Count -eq 0) {
    Write-Verbose "No new events since RecordId $lastRecordId."
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

$out | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

# ---------------------------------------------------------------------------
# 5. Persist state (bookmark + still-open processes)
# ---------------------------------------------------------------------------
@{ LastRecordId = $maxRecordId; UpdatedAt = $now } |
    ConvertTo-Json | Set-Content $StatePath -Encoding UTF8

# Prune very old open entries (>24h) so a missed 4689 doesn't leak forever
$cutoff = (Get-Date).AddHours(-24).Ticks
$openClean = @{}
foreach ($k in $open.Keys) { if ($open[$k] -ge $cutoff) { $openClean[$k] = $open[$k] } }
($openClean | ConvertTo-Json) | Set-Content $openPath -Encoding UTF8

Write-Verbose "Processed $($events.Count) events up to RecordId $maxRecordId."