# ============================================================
# Enhanced Directory Size Discovery Script
# ============================================================
# This script efficiently scans a drive to identify large directories
# and helps pinpoint where disk space is being consumed.
#
# Key Features:
# - Excludes junction points and symbolic links to avoid double-counting
# - Bottom-up size calculation for efficiency
# - Progress tracking with Write-Progress
# - Detailed CSV export with metadata

[CmdletBinding()]
param(
    [string]$DrivePath = "C:\",
    [decimal]$ThresholdGB = 0.5,
    [int]$MaxDepth = 10,
    [string]$OutputPath = "$env:USERPROFILE\Documents\DirectorySizeReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",
    [switch]$IncludeJunctions
)

# Check for Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "This script is not running with Administrator privileges. Some directories may be inaccessible."
    $continue = Read-Host "Continue anyway? (Y/N)"
    if ($continue -ne 'Y') { exit }
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Directory Size Discovery Tool" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Scanning: $DrivePath" -ForegroundColor White
Write-Host "Size threshold: $ThresholdGB GB" -ForegroundColor White
Write-Host "Max depth: $MaxDepth levels" -ForegroundColor White
Write-Host "Junction points: $(if ($IncludeJunctions) { 'Included (may double-count)' } else { 'Excluded (recommended)' })" -ForegroundColor White
Write-Host "Output file: $OutputPath" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Starting scan... This may take several minutes." -ForegroundColor Yellow
Write-Host ""

# Start performance timer
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Error tracking
$script:inaccessibleDirs = 0
$script:inaccessibleFiles = 0

# Function to test if a path is a junction point or symbolic link
function Test-ReparsePoint {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $false }

    try {
        $item = Get-Item -Path $Path -Force -ErrorAction Stop
        return ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint
    }
    catch {
        return $false
    }
}

# Function to calculate directory size efficiently (non-recursive per folder)
function Get-DirectorySize {
    param([string]$Path)

    $totalSize = 0
    try {
        # Only get files in THIS directory (not recursive)
        $files = Get-ChildItem -Path $Path -File -Force -ErrorAction Stop
        foreach ($file in $files) {
            $totalSize += $file.Length
        }
    }
    catch {
        # Track inaccessible files
        $script:inaccessibleFiles++
        Write-Verbose "Cannot access files in: $Path"
    }
    return $totalSize
}

# Build directory tree with sizes
$directorySizes = @{}
$allDirectories = @()

Write-Host "[1/3] Discovering directory structure..." -ForegroundColor Cyan

# Get all directories up to max depth
try {
    Write-Progress -Activity "Discovering directories" -Status "Scanning file system..." -Id 1

    $directories = Get-ChildItem -Path $DrivePath -Directory -Recurse -Depth $MaxDepth -Force -ErrorAction SilentlyContinue

    # Filter out junction points and symbolic links unless explicitly included
    if (-not $IncludeJunctions) {
        $directories = $directories | Where-Object {
            -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
        }
    }

    $allDirectories = @($DrivePath) + $directories.FullName

    Write-Progress -Activity "Discovering directories" -Completed -Id 1
}
catch {
    Write-Warning "Error scanning directories: $_"
    $allDirectories = @($DrivePath)
}

Write-Host "  Found $($allDirectories.Count) directories to analyze" -ForegroundColor Green
if (-not $IncludeJunctions) {
    Write-Host "  (Junction points and symbolic links excluded)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "[2/3] Calculating directory sizes..." -ForegroundColor Cyan

# Calculate sizes from deepest to shallowest (bottom-up approach)
$sortedDirs = $allDirectories | Sort-Object { $_.Split('\').Count } -Descending

$processed = 0
$total = $sortedDirs.Count

foreach ($dir in $sortedDirs) {
    # Progress indicator using Write-Progress
    $processed++
    $percent = [math]::Floor(($processed / $total) * 100)

    Write-Progress -Activity "Calculating directory sizes" `
                   -Status "$processed of $total directories ($percent%)" `
                   -PercentComplete $percent `
                   -CurrentOperation "Processing: $dir" `
                   -Id 1

    # Get size of files in this directory only
    $ownSize = Get-DirectorySize -Path $dir

    # Get total size from subdirectories already calculated
    $subDirSize = 0
    try {
        $subDirs = Get-ChildItem -Path $dir -Directory -Force -ErrorAction Stop

        # Filter out junction points from subdirectories too
        if (-not $IncludeJunctions) {
            $subDirs = $subDirs | Where-Object {
                -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
            }
        }

        foreach ($subDir in $subDirs) {
            if ($directorySizes.ContainsKey($subDir.FullName)) {
                $subDirSize += $directorySizes[$subDir.FullName]
            }
        }
    }
    catch {
        # Track inaccessible subdirectories
        $script:inaccessibleDirs++
        Write-Verbose "Cannot access subdirectories in: $dir"
    }

    # Total size = own files + subdirectories
    $directorySizes[$dir] = $ownSize + $subDirSize
}

# Clear progress bar
Write-Progress -Activity "Calculating directory sizes" -Completed -Id 1

Write-Host ""
Write-Host "[3/3] Generating report..." -ForegroundColor Cyan

# Normalize drive path for depth calculation
$normalizedDrivePath = $DrivePath.TrimEnd('\')
$driveDepth = $normalizedDrivePath.Split('\').Count

# Convert to objects and filter by threshold
$results = $directorySizes.GetEnumerator() | ForEach-Object {
    $sizeGB = [math]::Round($_.Value / 1GB, 2)
    if ($sizeGB -ge $ThresholdGB) {
        $path = $_.Key
        $normalizedPath = $path.TrimEnd('\')

        [PSCustomObject]@{
            Directory   = $path
            SizeGB      = $sizeGB
            SizeMB      = [math]::Round($_.Value / 1MB, 2)
            Depth       = $normalizedPath.Split('\').Count - $driveDepth
            IsJunction  = Test-ReparsePoint -Path $path
        }
    }
} | Sort-Object -Property SizeGB -Descending

# Stop timer
$stopwatch.Stop()

# Display top 50 results
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "TOP LARGEST DIRECTORIES (>= $ThresholdGB GB)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
$results | Select-Object -First 50 | Format-Table -AutoSize -Wrap

# Export full results to CSV
$results | Export-Csv -Path $OutputPath -NoTypeInformation

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Scan completed in: " -NoNewline -ForegroundColor White
Write-Host "$($stopwatch.Elapsed.ToString('mm\:ss'))" -ForegroundColor Green
Write-Host ""
Write-Host "Total directories scanned: " -NoNewline -ForegroundColor White
Write-Host "$($allDirectories.Count)" -ForegroundColor Yellow
Write-Host "Directories over threshold: " -NoNewline -ForegroundColor White
Write-Host "$($results.Count)" -ForegroundColor Yellow

if ($script:inaccessibleDirs -gt 0 -or $script:inaccessibleFiles -gt 0) {
    Write-Host ""
    Write-Host "Access Issues:" -ForegroundColor Yellow
    if ($script:inaccessibleDirs -gt 0) {
        Write-Host "  Inaccessible directories: $script:inaccessibleDirs" -ForegroundColor Gray
    }
    if ($script:inaccessibleFiles -gt 0) {
        Write-Host "  Inaccessible file locations: $script:inaccessibleFiles" -ForegroundColor Gray
    }
    Write-Host "  (Run as Administrator for full access)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Full report saved to: " -NoNewline -ForegroundColor White
Write-Host "$OutputPath" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# Show specific analysis for large directories
if ($results.Count -gt 0) {
    $largest = $results[0]
    Write-Host ""
    Write-Host "Largest directory found:" -ForegroundColor Green
    Write-Host "  Path: $($largest.Directory)" -ForegroundColor White
    Write-Host "  Size: $($largest.SizeGB) GB ($($largest.SizeMB) MB)" -ForegroundColor Yellow
    if ($largest.IsJunction) {
        Write-Host "  Type: Junction Point / Symbolic Link" -ForegroundColor Magenta
    }

    # Show top-level breakdown with numbering
    Write-Host ""
    Write-Host "Top-level directories:" -ForegroundColor Green
    $topLevel = $results | Where-Object { $_.Depth -eq 1 } | Sort-Object -Property SizeGB -Descending

    $index = 1
    $directoryMap = @{}

    foreach ($dir in $topLevel) {
        $directoryMap[$index] = $dir
        $junctionMarker = if ($dir.IsJunction) { " [JUNCTION]" } else { "" }
        $sizeDisplay = "$($dir.SizeGB) GB".PadLeft(12)
        $dirName = Split-Path $dir.Directory -Leaf

        Write-Host "  [$index] " -NoNewline -ForegroundColor Cyan
        Write-Host "$dirName".PadRight(35) -NoNewline -ForegroundColor $(if ($dir.IsJunction) { "Magenta" } else { "White" })
        Write-Host "$sizeDisplay$junctionMarker" -ForegroundColor Yellow

        $index++
    }

    # Interactive drill-down option
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "DRILL-DOWN OPTION" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "Enter a number to scan that directory in detail," -ForegroundColor White
    Write-Host "or press ENTER to exit:" -ForegroundColor White
    Write-Host ""

    $selection = Read-Host "Selection"

    if ($selection -match '^\d+$' -and $directoryMap.ContainsKey([int]$selection)) {
        $selectedDir = $directoryMap[[int]$selection]

        Write-Host ""
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "DRILLING INTO: $($selectedDir.Directory)" -ForegroundColor Green
        Write-Host "============================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Starting detailed scan..." -ForegroundColor Yellow
        Write-Host "Press Ctrl+C to cancel" -ForegroundColor Gray
        Start-Sleep -Seconds 2

        # Re-run the script on the selected directory
        $params = @{
            DrivePath = $selectedDir.Directory
            ThresholdGB = $ThresholdGB
            MaxDepth = $MaxDepth
            OutputPath = "$env:USERPROFILE\Documents\DirectorySizeReport_$(Split-Path $selectedDir.Directory -Leaf)_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        }

        if ($IncludeJunctions) {
            $params['IncludeJunctions'] = $true
        }

        # Recursively call this script
        if ($PSCommandPath) {
            & $PSCommandPath @params
        }
        else {
            Write-Warning "Cannot recursively drill down - script path not available."
            Write-Host "This happens when the script is not run as a saved .ps1 file." -ForegroundColor Yellow
            Write-Host "To enable drill-down, run the script directly from its file location." -ForegroundColor Yellow
        }
    }
    elseif ($selection -ne "") {
        Write-Host "Invalid selection. Exiting." -ForegroundColor Red
    }
}
