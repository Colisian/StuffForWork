# ============================================================
# Enhanced Directory Size Discovery Script
# ============================================================
# This script efficiently scans a drive to identify large directories
# and helps pinpoint where disk space is being consumed.

param(
    [string]$DrivePath = "C:\",
    [decimal]$ThresholdGB = 0.5,
    [int]$MaxDepth = 10,
    [string]$OutputPath = "$env:USERPROFILE\Documents\DirectorySizeReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

# Check for Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "This script is not running with Administrator privileges. Some directories may be inaccessible."
    $continue = Read-Host "Continue anyway? (Y/N)"
    if ($continue -ne 'Y') { exit }
}

Write-Output "============================================"
Write-Output "Directory Size Discovery Tool"
Write-Output "============================================"
Write-Output "Scanning: $DrivePath"
Write-Output "Size threshold: $ThresholdGB GB"
Write-Output "Max depth: $MaxDepth levels"
Write-Output "Output file: $OutputPath"
Write-Output "============================================"
Write-Output ""
Write-Output "Starting scan... This may take several minutes."
Write-Output ""

# Function to calculate directory size efficiently (non-recursive per folder)
function Get-DirectorySize {
    param([string]$Path)

    $totalSize = 0
    try {
        # Only get files in THIS directory (not recursive)
        $files = Get-ChildItem -Path $Path -File -Force -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $totalSize += $file.Length
        }
    }
    catch {
        # Silently skip inaccessible files
    }
    return $totalSize
}

# Build directory tree with sizes
$directorySizes = @{}
$allDirectories = @()

Write-Output "[1/3] Discovering directory structure..."

# Get all directories up to max depth
try {
    $directories = Get-ChildItem -Path $DrivePath -Directory -Recurse -Depth $MaxDepth -Force -ErrorAction SilentlyContinue
    $allDirectories = @($DrivePath) + $directories.FullName
}
catch {
    Write-Warning "Error scanning directories: $_"
    $allDirectories = @($DrivePath)
}

Write-Output "Found $($allDirectories.Count) directories to analyze."
Write-Output ""
Write-Output "[2/3] Calculating directory sizes..."

# Calculate sizes from deepest to shallowest (bottom-up approach)
$sortedDirs = $allDirectories | Sort-Object { $_.Split('\').Count } -Descending

$processed = 0
$total = $sortedDirs.Count
$lastPercent = 0

foreach ($dir in $sortedDirs) {
    # Progress indicator
    $processed++
    $percent = [math]::Floor(($processed / $total) * 100)
    if ($percent -ne $lastPercent -and $percent % 5 -eq 0) {
        Write-Output "Progress: $percent% ($processed/$total directories)"
        $lastPercent = $percent
    }

    # Get size of files in this directory only
    $ownSize = Get-DirectorySize -Path $dir

    # Get total size from subdirectories already calculated
    $subDirSize = 0
    try {
        $subDirs = Get-ChildItem -Path $dir -Directory -Force -ErrorAction SilentlyContinue
        foreach ($subDir in $subDirs) {
            if ($directorySizes.ContainsKey($subDir.FullName)) {
                $subDirSize += $directorySizes[$subDir.FullName]
            }
        }
    }
    catch {
        # Skip inaccessible subdirectories
    }

    # Total size = own files + subdirectories
    $directorySizes[$dir] = $ownSize + $subDirSize
}

Write-Output ""
Write-Output "[3/3] Generating report..."

# Convert to objects and filter by threshold
$results = $directorySizes.GetEnumerator() | ForEach-Object {
    $sizeGB = [math]::Round($_.Value / 1GB, 2)
    if ($sizeGB -ge $ThresholdGB) {
        [PSCustomObject]@{
            Directory = $_.Key
            SizeGB    = $sizeGB
            SizeMB    = [math]::Round($_.Value / 1MB, 2)
            Depth     = ($_.Key.Split('\').Count - $DrivePath.Split('\').Count + 1)
        }
    }
} | Sort-Object -Property SizeGB -Descending

# Display top 50 results
Write-Output ""
Write-Output "============================================"
Write-Output "TOP LARGEST DIRECTORIES (>= $ThresholdGB GB)"
Write-Output "============================================"
$results | Select-Object -First 50 | Format-Table -AutoSize

# Export full results to CSV
$results | Export-Csv -Path $OutputPath -NoTypeInformation

Write-Output ""
Write-Output "============================================"
Write-Output "SUMMARY"
Write-Output "============================================"
Write-Output "Total directories analyzed: $($allDirectories.Count)"
Write-Output "Directories over threshold: $($results.Count)"
Write-Output "Full report saved to: $OutputPath"
Write-Output "============================================"

# Show specific analysis for large directories
if ($results.Count -gt 0) {
    $largest = $results[0]
    Write-Output ""
    Write-Output "Largest directory found:"
    Write-Output "  Path: $($largest.Directory)"
    Write-Output "  Size: $($largest.SizeGB) GB"
}
