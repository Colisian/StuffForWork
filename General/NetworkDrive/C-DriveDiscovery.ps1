<#
.SYNOPSIS
    Scans a drive or folder tree to identify the directories and files consuming disk space.

.DESCRIPTION
    Walks the directory tree in a single pass, computing complete sizes bottom-up.

    Key behaviors:
    - MaxDepth limits how deep the REPORT goes; sizes are always computed from the
      full tree, so parent totals are never truncated.
    - Junction points and symbolic links are excluded from traversal by default,
      which prevents double-counting and junction cycles on both Windows
      PowerShell 5.1 and PowerShell 7.
    - OneDrive/Files On-Demand cloud-only placeholder files are tracked separately:
      SizeGB is the logical size, SizeOnDiskGB excludes placeholder bytes. On
      machines with Known Folder Move this is the difference between "big folder"
      and "big folder actually using local disk".
    - Tracks the top N largest individual files encountered during the scan.
    - Prints a drive capacity summary; when scanning a volume root it also shows
      how much used space the scan could not account for (pagefile, VSS shadow
      copies, System Volume Information, recycle bin, etc.).
    - Full results export to CSV; interactive drill-down runs in-process, so it
      works however the script is launched (file, dot-sourced, run-selection)
      and can be repeated to any depth.

      One note for real use: each drill-down is a full re-scan of that subtree, so on a big folder 
      there's a wait each time. If that gets annoying, a future improvement could cache the first 
      scan's results and drill instantly from memory — say the word and I'll add it.

.PARAMETER DrivePath
    Root of the scan. Defaults to C:\. Must be an existing directory.

.PARAMETER ThresholdGB
    Minimum logical size (GB) for a directory to appear in the report. Default 0.5.

.PARAMETER MaxDepth
    Maximum directory depth to include in the report (root = 0). Scanning always
    covers the full tree regardless of this value. Default 10.

.PARAMETER OutputPath
    CSV report destination. Defaults to a timestamped file in the user's Documents
    folder (follows OneDrive folder redirection). Drill-down scans write additional
    CSVs alongside it, named after the selected folder.

.PARAMETER TopFiles
    Number of largest individual files to report. 0 disables. Default 20.

.PARAMETER IncludeJunctions
    Traverse into junction points and symbolic links. May double-count data that
    is reachable by more than one path; a recursion-depth guard prevents infinite
    junction cycles.

.PARAMETER NonInteractive
    Suppress all prompts (admin confirmation, drill-down). Use for scheduled or
    remote execution (Intune, SSM Run Command).

.EXAMPLE
    .\C-DriveDiscovery.ps1
    Scan C:\ interactively with defaults.

.EXAMPLE
    .\C-DriveDiscovery.ps1 -DrivePath D:\Data -ThresholdGB 1 -TopFiles 50 -NonInteractive

.NOTES
    Author  : Oji (cmcleod1@umd.edu)
    Date    : 2026-07-17
    Version : 2.1
    - Sizes are logical file lengths; NTFS compression and sparse files are not
      adjusted, so SizeOnDiskGB is an approximation.
    - On Windows PowerShell 5.1 without LongPathsEnabled, paths over 260 chars
      may be skipped (counted under "inaccessible directories").
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$DrivePath = 'C:\',

    [ValidateRange(0, 1048576)]
    [decimal]$ThresholdGB = 0.5,

    [ValidateRange(1, 100)]
    [int]$MaxDepth = 10,

    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) "DirectorySizeReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"),

    [ValidateRange(0, 100)]
    [int]$TopFiles = 20,

    [switch]$IncludeJunctions,

    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

# FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS | RECALL_ON_OPEN | OFFLINE — cloud-only
# placeholders (OneDrive Files On-Demand) report full Length but occupy ~0 disk.
$script:cloudAttributeMask = 0x400000 -bor 0x40000 -bor 0x1000
$script:reparseAttribute   = [int][System.IO.FileAttributes]::ReparsePoint
$script:absoluteDepthLimit = 192   # cycle guard when -IncludeJunctions traverses looping junctions

$script:results          = [System.Collections.Generic.List[pscustomobject]]::new()
$script:topFileList      = [System.Collections.Generic.List[pscustomobject]]::new()
$script:topFileMin       = [long]0
$script:dirCount         = 0
$script:fileCount        = 0
$script:cloudFileCount   = 0
$script:inaccessibleDirs = 0
$script:progressTimer    = [System.Diagnostics.Stopwatch]::StartNew()

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Returns $true when running elevated on Windows (always $true elsewhere).
    #>
    [CmdletBinding()]
    param()

    if ([System.Environment]::OSVersion.Platform -ne 'Win32NT') { return $true }
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Measure-DirectoryTree {
    <#
    .SYNOPSIS
        Recursively totals a directory tree, recording report rows as it unwinds.
    .NOTES
        Returns an object with Logical, OnDisk, and Cloud byte totals for the tree.
        Enumerates each directory exactly once; skips reparse points unless
        -IncludeJunctions was passed to the script.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]$Directory,

        [Parameter(Mandatory)]
        [int]$Depth
    )

    $script:dirCount++
    if ($script:progressTimer.ElapsedMilliseconds -ge 250) {
        Write-Progress -Id 1 -Activity 'Scanning directory tree' `
            -Status "$($script:dirCount) directories, $($script:fileCount) files scanned" `
            -CurrentOperation $Directory.FullName
        $script:progressTimer.Restart()
    }

    [long]$logicalBytes = 0
    [long]$onDiskBytes  = 0
    [long]$cloudBytes   = 0

    try {
        foreach ($entry in $Directory.EnumerateFileSystemInfos()) {
            if ($entry -is [System.IO.FileInfo]) {
                $script:fileCount++
                $logicalBytes += $entry.Length

                if ($entry.Attributes.value__ -band $script:cloudAttributeMask) {
                    $script:cloudFileCount++
                    $cloudBytes += $entry.Length
                }
                else {
                    $onDiskBytes += $entry.Length
                }

                if ($TopFiles -gt 0 -and $entry.Length -gt $script:topFileMin) {
                    $script:topFileList.Add([pscustomobject]@{
                        File      = $entry.FullName
                        SizeBytes = $entry.Length
                    })
                    if ($script:topFileList.Count -ge ($TopFiles * 2)) {
                        $trimmed = $script:topFileList | Sort-Object SizeBytes -Descending | Select-Object -First $TopFiles
                        $script:topFileList = [System.Collections.Generic.List[pscustomobject]]@($trimmed)
                        $script:topFileMin  = $script:topFileList[$script:topFileList.Count - 1].SizeBytes
                    }
                }
            }
            else {
                $isReparse = ($entry.Attributes.value__ -band $script:reparseAttribute) -ne 0
                if ($isReparse -and -not $IncludeJunctions) { continue }
                if (($Depth + 1) -gt $script:absoluteDepthLimit) { continue }

                $subTotals = Measure-DirectoryTree -Directory $entry -Depth ($Depth + 1)
                $logicalBytes += $subTotals.Logical
                $onDiskBytes  += $subTotals.OnDisk
                $cloudBytes   += $subTotals.Cloud
            }
        }
    }
    catch {
        $script:inaccessibleDirs++
        Write-Verbose "Access denied or unreadable: $($Directory.FullName)"
    }

    if ($Depth -le $MaxDepth) {
        $script:results.Add([pscustomobject]@{
            Directory      = $Directory.FullName
            SizeGB         = [math]::Round($logicalBytes / 1GB, 2)
            SizeOnDiskGB   = [math]::Round($onDiskBytes / 1GB, 2)
            CloudOnlyGB    = [math]::Round($cloudBytes / 1GB, 2)
            Depth          = $Depth
            IsReparsePoint = ($Directory.Attributes.value__ -band $script:reparseAttribute) -ne 0
            SizeBytes      = $logicalBytes
        })
    }

    return [pscustomobject]@{
        Logical = $logicalBytes
        OnDisk  = $onDiskBytes
        Cloud   = $cloudBytes
    }
}

function Invoke-DiscoveryScan {
    <#
    .SYNOPSIS
        Scans one path, prints the full report, and returns the depth-1 rows
        so the caller can offer drill-down.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$CsvPath
    )

    # Reset per-scan state so drill-down scans start clean
    $script:results.Clear()
    $script:topFileList.Clear()
    $script:topFileMin       = [long]0
    $script:dirCount         = 0
    $script:fileCount        = 0
    $script:cloudFileCount   = 0
    $script:inaccessibleDirs = 0

    $root = Get-Item -LiteralPath $Path -Force

    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host 'Directory Size Discovery Tool' -ForegroundColor Cyan
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host "Scanning: $($root.FullName)" -ForegroundColor White
    Write-Host "Report threshold: $ThresholdGB GB" -ForegroundColor White
    Write-Host "Report depth: $MaxDepth levels (sizes always include the full tree)" -ForegroundColor White
    Write-Host "Junction points: $(if ($IncludeJunctions) { 'Traversed (may double-count)' } else { 'Excluded (recommended)' })" -ForegroundColor White
    Write-Host "Output file: $CsvPath" -ForegroundColor Gray
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Scanning... this may take several minutes on a full drive.' -ForegroundColor Yellow
    Write-Host ''

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $grandTotal = Measure-DirectoryTree -Directory $root -Depth 0
    }
    catch {
        Write-Warning "Scan failed: $_"
        return @()
    }
    finally {
        Write-Progress -Id 1 -Activity 'Scanning directory tree' -Completed
    }

    $stopwatch.Stop()

    # --- Report ---
    $thresholdBytes = [long]($ThresholdGB * 1GB)
    $report = @($script:results | Where-Object { $_.SizeBytes -ge $thresholdBytes } | Sort-Object SizeBytes -Descending)

    Write-Host ''
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host "TOP LARGEST DIRECTORIES (>= $ThresholdGB GB)" -ForegroundColor Cyan
    Write-Host '============================================' -ForegroundColor Cyan
    if ($report.Count -gt 0) {
        $report |
            Select-Object -First 50 -Property Directory, SizeGB, SizeOnDiskGB, CloudOnlyGB, Depth |
            Format-Table -AutoSize -Wrap | Out-Host
    }
    else {
        Write-Host "No directories at or above the $ThresholdGB GB threshold." -ForegroundColor Yellow
    }

    if ($TopFiles -gt 0 -and $script:topFileList.Count -gt 0) {
        Write-Host '============================================' -ForegroundColor Cyan
        Write-Host "TOP $TopFiles LARGEST FILES" -ForegroundColor Cyan
        Write-Host '============================================' -ForegroundColor Cyan
        $script:topFileList |
            Sort-Object SizeBytes -Descending |
            Select-Object -First $TopFiles -Property File,
                @{ Name = 'SizeGB'; Expression = { [math]::Round($_.SizeBytes / 1GB, 2) } },
                @{ Name = 'SizeMB'; Expression = { [math]::Round($_.SizeBytes / 1MB, 1) } } |
            Format-Table -AutoSize -Wrap | Out-Host
    }

    if ($report.Count -gt 0) {
        $report | Select-Object Directory, SizeGB, SizeOnDiskGB, CloudOnlyGB, Depth, IsReparsePoint, SizeBytes |
            Export-Csv -Path $CsvPath -NoTypeInformation
    }

    # --- Summary ---
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host 'SUMMARY' -ForegroundColor Cyan
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host "Scan time:           $($stopwatch.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor White
    Write-Host "Directories scanned: $($script:dirCount)" -ForegroundColor White
    Write-Host "Files scanned:       $($script:fileCount)" -ForegroundColor White
    Write-Host "Total size:          $([math]::Round($grandTotal.Logical / 1GB, 2)) GB logical / $([math]::Round($grandTotal.OnDisk / 1GB, 2)) GB on disk" -ForegroundColor Yellow
    if ($script:cloudFileCount -gt 0) {
        Write-Host "Cloud-only files:    $($script:cloudFileCount) ($([math]::Round($grandTotal.Cloud / 1GB, 2)) GB not occupying local disk)" -ForegroundColor Magenta
    }
    Write-Host "Over threshold:      $($report.Count) directories" -ForegroundColor White
    if ($script:inaccessibleDirs -gt 0) {
        Write-Host "Inaccessible dirs:   $($script:inaccessibleDirs) (run as Administrator for full access)" -ForegroundColor Yellow
    }

    try {
        $driveInfo = [System.IO.DriveInfo]::new($root.Root.FullName)
        if ($driveInfo.IsReady) {
            $usedBytes = $driveInfo.TotalSize - $driveInfo.TotalFreeSpace
            Write-Host ''
            Write-Host "Volume $($driveInfo.Name)  $([math]::Round($driveInfo.TotalSize / 1GB, 1)) GB total, $([math]::Round($usedBytes / 1GB, 1)) GB used, $([math]::Round($driveInfo.TotalFreeSpace / 1GB, 1)) GB free" -ForegroundColor White
            if ($root.FullName.TrimEnd('\', '/') -eq $root.Root.FullName.TrimEnd('\', '/')) {
                $unaccounted = $usedBytes - $grandTotal.OnDisk
                if ($unaccounted -gt 1GB) {
                    Write-Host "Unaccounted space:   $([math]::Round($unaccounted / 1GB, 1)) GB (pagefile, shadow copies, System Volume Information, recycle bin, NTFS overhead, or inaccessible dirs)" -ForegroundColor Gray
                }
            }
        }
    }
    catch {
        Write-Verbose "Could not read volume information: $_"
    }

    Write-Host ''
    if ($report.Count -gt 0) {
        Write-Host "Full report saved to: $CsvPath" -ForegroundColor Cyan
    }
    else {
        Write-Host 'No CSV written (no directories over threshold).' -ForegroundColor Gray
    }
    Write-Host '============================================' -ForegroundColor Cyan

    return @($report | Where-Object { $_.Depth -eq 1 })
}

# ============================================================
# Main
# ============================================================

$isInteractive = (-not $NonInteractive) -and [Environment]::UserInteractive

if (-not (Test-IsAdministrator)) {
    Write-Warning 'Not running as Administrator - some directories will be inaccessible and totals will undercount.'
    if ($isInteractive) {
        $continue = Read-Host 'Continue anyway? (Y/N)'
        if ($continue -notmatch '^y') { return }
    }
}

$csvFolder   = Split-Path -Path $OutputPath -Parent
$currentPath = $DrivePath
$currentCsv  = $OutputPath

# Scan, then loop: each drill-down selection re-scans in-process, so this works
# no matter how the script was launched and supports unlimited drill depth.
while ($true) {
    $topLevel = @(Invoke-DiscoveryScan -Path $currentPath -CsvPath $currentCsv)

    if ($topLevel.Count -eq 0) { break }

    Write-Host ''
    Write-Host 'Top-level directories:' -ForegroundColor Green

    $index = 1
    $directoryMap = @{}
    foreach ($dir in $topLevel) {
        $directoryMap[$index] = $dir
        $marker = if ($dir.IsReparsePoint) { ' [JUNCTION]' } else { '' }
        $sizeDisplay = "$($dir.SizeGB) GB".PadLeft(12)
        $dirName = Split-Path $dir.Directory -Leaf

        Write-Host "  [$index] " -NoNewline -ForegroundColor Cyan
        Write-Host "$dirName".PadRight(35) -NoNewline -ForegroundColor $(if ($dir.IsReparsePoint) { 'Magenta' } else { 'White' })
        Write-Host "$sizeDisplay$marker" -ForegroundColor Yellow
        $index++
    }

    if (-not $isInteractive) { break }

    Write-Host ''
    Write-Host 'Enter a number to drill into that directory, or press ENTER to exit:' -ForegroundColor White
    $selection = Read-Host 'Selection'

    if ($selection -match '^\d+$' -and $directoryMap.ContainsKey([int]$selection)) {
        $selectedDir = $directoryMap[[int]$selection]

        Write-Host ''
        Write-Host "Drilling into: $($selectedDir.Directory)" -ForegroundColor Green
        Write-Host ''

        $currentPath = $selectedDir.Directory
        $currentCsv  = Join-Path $csvFolder "DirectorySizeReport_$(Split-Path $selectedDir.Directory -Leaf)_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        continue
    }

    if ($selection -ne '') {
        Write-Host 'Invalid selection. Exiting.' -ForegroundColor Red
    }
    break
}
