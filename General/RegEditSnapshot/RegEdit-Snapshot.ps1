<#
.SYNOPSIS
    Captures before/after registry snapshots and identifies all changes between them.
    
.DESCRIPTION
    This script takes a complete (or scoped) registry snapshot, allows the user to make changes,
    then captures another snapshot and shows exactly what changed in the registry.

    ## Key Improvements

 1. **Clean Progress Display**
- Changed from spamming progress lines to a single updating progress bar
- Uses Unicode block characters (█░) for visual appeal
- Only updates every 50 keys for better performance
- Clears progress line when complete

2. **Fixed Path Length Issues**
- Added `Get-SafeFileName` function that:
  - Truncates long paths intelligently
  - Adds SHA256 hash to preserve uniqueness
  - Keeps extensions intact
- Uses sequential numbering (`Binary_0001`, `Binary_0002`) instead of long registry paths
- Creates a mapping file (`00_FileMapping.txt`) to link numbers to actual registry paths

3. **Better Analysis Feedback**
- Shows what stage of comparison is running
- Cleaner final output with limited preview (3 items instead of 5)
- Suppresses `Stop-Transcript` output

4. **Reduced Verbosity**
- Only shows total counts at the end
- Progress bar updates in place instead of new lines
- Removed redundant "Excluded paths" detail unless verbose

The output will now look like:
```
Capturing BEFORE snapshot...
  Scanning: HKCU:\
  Counting registry items...
  Found 14478 keys to process
  Processing keys: [██████████████████████████████] 100% (14478/14478)
  Complete: 14478 keys, 33843 values (11.9s)
    
.PARAMETER Scope
    Specify which registry hives to monitor:
    - CurrentUser (default, fastest)
    - AllUsers (HKCU + common paths)
    - System (includes HKLM)
    - Full (entire registry, very slow)
    - Custom (specify paths manually)
    
.PARAMETER ExcludePaths
    Array of registry paths to exclude (e.g., volatile keys that always change)
    
.EXAMPLE
    .\Compare-RegistryChanges.ps1 -Scope CurrentUser
    
.NOTES
    Author: UMD Libraries IT
    Version: 2.1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('CurrentUser', 'AllUsers', 'System', 'Full', 'Custom')]
    [string]$Scope = 'CurrentUser',
    
    [Parameter()]
    [string[]]$CustomPaths = @(),
    
    [Parameter()]
    [string[]]$ExcludePaths = @(),
    
    [Parameter()]
    [string]$OutputFolder = (Join-Path $env:USERPROFILE "Desktop\RegistryAnalysis"),
    
    [Parameter()]
    [switch]$IncludePermissions,
    
    [Parameter()]
    [switch]$Verbose
)

# Default volatile/noisy paths to exclude
$defaultExclusions = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders',
    'HKCU:\Volatile Environment',
    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management',
    'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Reliability',
    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Prefetcher',
    'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections',
    'HKCU:\Software\Microsoft\Office\*\Common\Open Find',
    'HKCU:\Software\Classes\Local Settings\MuiCache'
)

$allExclusions = $defaultExclusions + $ExcludePaths

# Define scope paths
$scopePaths = switch ($Scope) {
    'CurrentUser' {
        @('HKCU:\')
    }
    'AllUsers' {
        @(
            'HKCU:\',
            'HKLM:\SOFTWARE\',
            'HKLM:\SYSTEM\CurrentControlSet\Services'
        )
    }
    'System' {
        @(
            'HKCU:\',
            'HKLM:\SOFTWARE\',
            'HKLM:\SYSTEM\',
            'HKU:\.DEFAULT'
        )
    }
    'Full' {
        @(
            'HKCU:\',
            'HKLM:\',
            'HKCR:\',
            'HKU:\'
        )
    }
    'Custom' {
        if ($CustomPaths.Count -eq 0) {
            Write-Host "Error: Custom scope requires -CustomPaths parameter" -ForegroundColor Red
            exit 1
        }
        $CustomPaths
    }
}

# Create output folder
if (-not (Test-Path $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
}

# Logging
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $OutputFolder "Analysis_$timestamp.log"
Start-Transcript -Path $logFile

function Test-ShouldExcludePath {
    param([string]$Path)
    
    foreach ($exclusion in $allExclusions) {
        if ($Path -like $exclusion -or $Path -like "$exclusion*") {
            return $true
        }
    }
    return $false
}

function Write-ProgressBar {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Activity = "Processing",
        [int]$BarLength = 50
    )
    
    if ($Total -eq 0) { return }
    
    $percent = [math]::Min(100, [math]::Round(($Current / $Total) * 100))
    $filledLength = [math]::Round(($BarLength * $Current) / $Total)
    $bar = ('█' * $filledLength) + ('░' * ($BarLength - $filledLength))
    
    Write-Host "`r  $Activity`: [$bar] $percent% ($Current/$Total)" -NoNewline -ForegroundColor Cyan
}

function Get-SafeFileName {
    param(
        [string]$FileName,
        [int]$MaxLength = 200
    )
    
    # Remove invalid characters
    $safe = $FileName -replace '[\\/:*?"<>|]', '_'
    
    # Truncate if too long, but preserve extension
    if ($safe.Length -gt $MaxLength) {
        $extension = [System.IO.Path]::GetExtension($safe)
        $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($safe)
        $maxNameLength = $MaxLength - $extension.Length - 10  # Leave room for hash
        
        if ($maxNameLength -gt 0) {
            # Use first part of name + hash of full name
            $hash = [System.BitConverter]::ToString(
                [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                    [System.Text.Encoding]::UTF8.GetBytes($safe)
                )
            ).Replace('-','').Substring(0, 8)
            
            $safe = $nameWithoutExt.Substring(0, $maxNameLength) + "_" + $hash + $extension
        }
    }
    
    return $safe
}

function Get-RegistrySnapshot {
    param(
        [string[]]$RootPaths,
        [string]$SnapshotName = "Snapshot"
    )
    
    Write-Host ""
    Write-Host "Capturing $SnapshotName..." -ForegroundColor Cyan
    
    $snapshot = @{
        Keys = @{}
        Values = @{}
        Timestamp = Get-Date
        Scope = $Scope
    }
    
    $keyCount = 0
    $valueCount = 0
    $startTime = Get-Date
    
    foreach ($rootPath in $RootPaths) {
        Write-Host "  Scanning: $rootPath" -ForegroundColor Yellow
        
        try {
            # First pass: count total items for progress bar
            Write-Host "  Counting registry items..." -ForegroundColor Gray
            $allKeys = @(Get-ChildItem -Path $rootPath -Recurse -ErrorAction SilentlyContinue | 
                        Where-Object { -not (Test-ShouldExcludePath -Path $_.PSPath) })
            
            $totalKeys = $allKeys.Count
            Write-Host "  Found $totalKeys keys to process" -ForegroundColor Gray
            
            # Second pass: process with progress bar
            $processedKeys = 0
            
            foreach ($key in $allKeys) {
                $processedKeys++
                $keyCount++
                
                # Update progress bar every 50 keys
                if ($processedKeys % 50 -eq 0 -or $processedKeys -eq $totalKeys) {
                    Write-ProgressBar -Current $processedKeys -Total $totalKeys -Activity "Processing keys"
                }
                
                $keyPath = $key.PSPath -replace 'Microsoft.PowerShell.Core\\Registry::', ''
                
                $snapshot.Keys[$keyPath] = @{
                    Exists = $true
                    SubKeyCount = $key.SubKeyCount
                    ValueCount = $key.ValueCount
                }
                
                try {
                    $properties = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                    
                    if ($properties) {
                        $psProperties = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')
                        
                        $properties.PSObject.Properties | Where-Object { 
                            $_.Name -notin $psProperties 
                        } | ForEach-Object {
                            $valueCount++
                            $valuePath = "$keyPath\$($_.Name)"
                            
                            $snapshot.Values[$valuePath] = @{
                                Key = $keyPath
                                Name = $_.Name
                                Data = $_.Value
                                Type = $_.TypeNameOfValue
                            }
                        }
                    }
                } catch {
                    if ($Verbose) {
                        Write-Verbose "Could not read values from: $keyPath"
                    }
                }
                
                if ($IncludePermissions) {
                    try {
                        $acl = Get-Acl -Path $key.PSPath -ErrorAction SilentlyContinue
                        $snapshot.Keys[$keyPath].ACL = $acl
                    } catch {}
                }
            }
            
            # Clear the progress line
            Write-Host "`r" + (' ' * 100) + "`r" -NoNewline
            
        } catch {
            Write-Warning "Error scanning $rootPath : $_"
        }
    }
    
    $elapsed = (Get-Date) - $startTime
    Write-Host "  Complete: $keyCount keys, $valueCount values ($('{0:N1}' -f $elapsed.TotalSeconds)s)" -ForegroundColor Green
    
    return $snapshot
}

function Compare-RegistrySnapshots {
    param(
        [hashtable]$Before,
        [hashtable]$After
    )
    
    Write-Host ""
    Write-Host "Analyzing changes..." -ForegroundColor Cyan
    
    $changes = @{
        KeysAdded = @()
        KeysDeleted = @()
        ValuesAdded = @()
        ValuesDeleted = @()
        ValuesModified = @()
        Summary = @{}
    }
    
    # Find new keys
    Write-Host "  Checking for new keys..." -ForegroundColor Gray
    foreach ($keyPath in $After.Keys.Keys) {
        if (-not $Before.Keys.ContainsKey($keyPath)) {
            $changes.KeysAdded += $keyPath
        }
    }
    
    # Find deleted keys
    Write-Host "  Checking for deleted keys..." -ForegroundColor Gray
    foreach ($keyPath in $Before.Keys.Keys) {
        if (-not $After.Keys.ContainsKey($keyPath)) {
            $changes.KeysDeleted += $keyPath
        }
    }
    
    # Find value changes
    Write-Host "  Checking for new values..." -ForegroundColor Gray
    foreach ($valuePath in $After.Values.Keys) {
        if (-not $Before.Values.ContainsKey($valuePath)) {
            $changes.ValuesAdded += [PSCustomObject]@{
                Path = $valuePath
                Key = $After.Values[$valuePath].Key
                Name = $After.Values[$valuePath].Name
                NewData = $After.Values[$valuePath].Data
                Type = $After.Values[$valuePath].Type
            }
        }
    }
    
    Write-Host "  Checking for deleted values..." -ForegroundColor Gray
    foreach ($valuePath in $Before.Values.Keys) {
        if (-not $After.Values.ContainsKey($valuePath)) {
            $changes.ValuesDeleted += [PSCustomObject]@{
                Path = $valuePath
                Key = $Before.Values[$valuePath].Key
                Name = $Before.Values[$valuePath].Name
                OldData = $Before.Values[$valuePath].Data
                Type = $Before.Values[$valuePath].Type
            }
        }
    }
    
    Write-Host "  Checking for modified values..." -ForegroundColor Gray
    foreach ($valuePath in $After.Values.Keys) {
        if ($Before.Values.ContainsKey($valuePath)) {
            $oldValue = $Before.Values[$valuePath]
            $newValue = $After.Values[$valuePath]
            
            $dataChanged = $false
            
            if ($oldValue.Data -is [byte[]] -and $newValue.Data -is [byte[]]) {
                if ($oldValue.Data.Length -ne $newValue.Data.Length) {
                    $dataChanged = $true
                } else {
                    for ($i = 0; $i -lt $oldValue.Data.Length; $i++) {
                        if ($oldValue.Data[$i] -ne $newValue.Data[$i]) {
                            $dataChanged = $true
                            break
                        }
                    }
                }
            } else {
                $dataChanged = ($oldValue.Data -ne $newValue.Data)
            }
            
            if ($dataChanged) {
                $changes.ValuesModified += [PSCustomObject]@{
                    Path = $valuePath
                    Key = $newValue.Key
                    Name = $newValue.Name
                    OldData = $oldValue.Data
                    NewData = $newValue.Data
                    Type = $newValue.Type
                }
            }
        }
    }
    
    $changes.Summary = @{
        KeysAdded = $changes.KeysAdded.Count
        KeysDeleted = $changes.KeysDeleted.Count
        ValuesAdded = $changes.ValuesAdded.Count
        ValuesDeleted = $changes.ValuesDeleted.Count
        ValuesModified = $changes.ValuesModified.Count
        TotalChanges = $changes.KeysAdded.Count + $changes.KeysDeleted.Count + 
                       $changes.ValuesAdded.Count + $changes.ValuesDeleted.Count + 
                       $changes.ValuesModified.Count
    }
    
    return $changes
}

function Export-ChangesReport {
    param(
        [hashtable]$Changes,
        [string]$OutputPath
    )
    
    $reportFile = Join-Path $OutputPath "Registry_Changes_$timestamp.txt"
    $csvFile = Join-Path $OutputPath "Registry_Changes_$timestamp.csv"
    
    # Generate text report
    $report = @"
REGISTRY CHANGE ANALYSIS
========================
Analysis Date: $(Get-Date)
Scope: $Scope
Time Between Snapshots: $(($Changes.Summary.TimeBetweenSnapshots))

SUMMARY
-------
Total Changes Detected: $($Changes.Summary.TotalChanges)
  - Keys Added:     $($Changes.Summary.KeysAdded)
  - Keys Deleted:   $($Changes.Summary.KeysDeleted)
  - Values Added:   $($Changes.Summary.ValuesAdded)
  - Values Deleted: $($Changes.Summary.ValuesDeleted)
  - Values Modified: $($Changes.Summary.ValuesModified)


"@

    if ($Changes.KeysAdded.Count -gt 0) {
        $report += @"
KEYS ADDED ($($Changes.KeysAdded.Count))
----------
"@
        foreach ($key in $Changes.KeysAdded | Sort-Object) {
            $report += "`n  + $key"
        }
        $report += "`n`n"
    }
    
    if ($Changes.KeysDeleted.Count -gt 0) {
        $report += @"
KEYS DELETED ($($Changes.KeysDeleted.Count))
------------
"@
        foreach ($key in $Changes.KeysDeleted | Sort-Object) {
            $report += "`n  - $key"
        }
        $report += "`n`n"
    }
    
    if ($Changes.ValuesAdded.Count -gt 0) {
        $report += @"
VALUES ADDED ($($Changes.ValuesAdded.Count))
------------
"@
        foreach ($value in $Changes.ValuesAdded | Sort-Object -Property Key, Name) {
            $report += "`n  Key:  $($value.Key)"
            $report += "`n  Name: $($value.Name)"
            $report += "`n  Type: $($value.Type)"
            
            if ($value.NewData -is [byte[]]) {
                $hexData = ($value.NewData | ForEach-Object { "{0:X2}" -f $_ }) -join ' '
                if ($hexData.Length -gt 100) {
                    $hexData = $hexData.Substring(0, 100) + "... ($($value.NewData.Length) bytes)"
                }
                $report += "`n  Data: [BINARY] $hexData"
            } else {
                $dataStr = "$($value.NewData)"
                if ($dataStr.Length -gt 200) {
                    $dataStr = $dataStr.Substring(0, 200) + "..."
                }
                $report += "`n  Data: $dataStr"
            }
            $report += "`n"
        }
        $report += "`n"
    }
    
    if ($Changes.ValuesDeleted.Count -gt 0) {
        $report += @"
VALUES DELETED ($($Changes.ValuesDeleted.Count))
--------------
"@
        foreach ($value in $Changes.ValuesDeleted | Sort-Object -Property Key, Name) {
            $report += "`n  Key:  $($value.Key)"
            $report += "`n  Name: $($value.Name)"
            $report += "`n  Type: $($value.Type)"
            
            if ($value.OldData -is [byte[]]) {
                $hexData = ($value.OldData | ForEach-Object { "{0:X2}" -f $_ }) -join ' '
                if ($hexData.Length -gt 100) {
                    $hexData = $hexData.Substring(0, 100) + "... ($($value.OldData.Length) bytes)"
                }
                $report += "`n  Data: [BINARY] $hexData"
            } else {
                $dataStr = "$($value.OldData)"
                if ($dataStr.Length -gt 200) {
                    $dataStr = $dataStr.Substring(0, 200) + "..."
                }
                $report += "`n  Data: $dataStr"
            }
            $report += "`n"
        }
        $report += "`n"
    }
    
    if ($Changes.ValuesModified.Count -gt 0) {
        $report += @"
VALUES MODIFIED ($($Changes.ValuesModified.Count))
---------------
"@
        foreach ($value in $Changes.ValuesModified | Sort-Object -Property Key, Name) {
            $report += "`n  Key:  $($value.Key)"
            $report += "`n  Name: $($value.Name)"
            $report += "`n  Type: $($value.Type)"
            
            if ($value.OldData -is [byte[]]) {
                $oldHex = ($value.OldData | ForEach-Object { "{0:X2}" -f $_ }) -join ' '
                $newHex = ($value.NewData | ForEach-Object { "{0:X2}" -f $_ }) -join ' '
                
                if ($oldHex.Length -gt 100) { $oldHex = $oldHex.Substring(0, 100) + "..." }
                if ($newHex.Length -gt 100) { $newHex = $newHex.Substring(0, 100) + "..." }
                
                $report += "`n  Old:  [BINARY] $oldHex"
                $report += "`n  New:  [BINARY] $newHex"
                
                # Show byte differences
                if ($value.OldData.Length -eq $value.NewData.Length -and $value.OldData.Length -lt 1000) {
                    $diffs = @()
                    for ($i = 0; $i -lt $value.OldData.Length; $i++) {
                        if ($value.OldData[$i] -ne $value.NewData[$i]) {
                            $diffs += "Offset $i : 0x$("{0:X2}" -f $value.OldData[$i]) -> 0x$("{0:X2}" -f $value.NewData[$i])"
                        }
                    }
                    if ($diffs.Count -gt 0 -and $diffs.Count -lt 20) {
                        $report += "`n  Byte Differences:"
                        foreach ($diff in $diffs) {
                            $report += "`n    $diff"
                        }
                    }
                }
            } else {
                $oldStr = "$($value.OldData)"
                $newStr = "$($value.NewData)"
                if ($oldStr.Length -gt 200) { $oldStr = $oldStr.Substring(0, 200) + "..." }
                if ($newStr.Length -gt 200) { $newStr = $newStr.Substring(0, 200) + "..." }
                $report += "`n  Old:  $oldStr"
                $report += "`n  New:  $newStr"
            }
            $report += "`n"
        }
    }
    
    # Save text report
    $report | Out-File -FilePath $reportFile -Encoding UTF8
    Write-Host "Text report saved: $reportFile" -ForegroundColor Green
    
    # Generate CSV for easy filtering/analysis
    $csvData = @()
    
    foreach ($key in $Changes.KeysAdded) {
        $csvData += [PSCustomObject]@{
            ChangeType = 'KeyAdded'
            RegistryKey = $key
            ValueName = ''
            OldData = ''
            NewData = ''
            DataType = ''
        }
    }
    
    foreach ($key in $Changes.KeysDeleted) {
        $csvData += [PSCustomObject]@{
            ChangeType = 'KeyDeleted'
            RegistryKey = $key
            ValueName = ''
            OldData = ''
            NewData = ''
            DataType = ''
        }
    }
    
    foreach ($value in $Changes.ValuesAdded) {
        $newData = if ($value.NewData -is [byte[]]) {
            "[BINARY: $($value.NewData.Length) bytes]"
        } else {
            "$($value.NewData)"
        }
        
        $csvData += [PSCustomObject]@{
            ChangeType = 'ValueAdded'
            RegistryKey = $value.Key
            ValueName = $value.Name
            OldData = ''
            NewData = $newData
            DataType = $value.Type
        }
    }
    
    foreach ($value in $Changes.ValuesDeleted) {
        $oldData = if ($value.OldData -is [byte[]]) {
            "[BINARY: $($value.OldData.Length) bytes]"
        } else {
            "$($value.OldData)"
        }
        
        $csvData += [PSCustomObject]@{
            ChangeType = 'ValueDeleted'
            RegistryKey = $value.Key
            ValueName = $value.Name
            OldData = $oldData
            NewData = ''
            DataType = $value.Type
        }
    }
    
    foreach ($value in $Changes.ValuesModified) {
        $oldData = if ($value.OldData -is [byte[]]) {
            "[BINARY: $($value.OldData.Length) bytes]"
        } else {
            "$($value.OldData)"
        }
        
        $newData = if ($value.NewData -is [byte[]]) {
            "[BINARY: $($value.NewData.Length) bytes]"
        } else {
            "$($value.NewData)"
        }
        
        $csvData += [PSCustomObject]@{
            ChangeType = 'ValueModified'
            RegistryKey = $value.Key
            ValueName = $value.Name
            OldData = $oldData
            NewData = $newData
            DataType = $value.Type
        }
    }
    
    $csvData | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
    Write-Host "CSV report saved: $csvFile" -ForegroundColor Green
    
    # Save binary data for modified values with improved filename handling
    $binaryFolder = Join-Path $OutputPath "BinaryData_$timestamp"
    $hasBinaryChanges = $false
    $binaryIndex = 1
    
    foreach ($value in $Changes.ValuesModified) {
        if ($value.OldData -is [byte[]] -or $value.NewData -is [byte[]]) {
            if (-not $hasBinaryChanges) {
                New-Item -Path $binaryFolder -ItemType Directory -Force | Out-Null
                $hasBinaryChanges = $true
            }
            
            # Create a safe, short filename using an index
            $safeBaseName = "Binary_$($binaryIndex.ToString('D4'))"
            
            # Also create a mapping file
            $mappingFile = Join-Path $binaryFolder "00_FileMapping.txt"
            $mappingEntry = @"
[$binaryIndex] $safeBaseName
Key: $($value.Key)
Value: $($value.Name)
Type: $($value.Type)
--------------------

"@
            Add-Content -Path $mappingFile -Value $mappingEntry -Encoding UTF8
            
            try {
                if ($value.OldData -is [byte[]]) {
                    $oldFile = Join-Path $binaryFolder "$safeBaseName`_OLD.bin"
                    [System.IO.File]::WriteAllBytes($oldFile, $value.OldData)
                }
                
                if ($value.NewData -is [byte[]]) {
                    $newFile = Join-Path $binaryFolder "$safeBaseName`_NEW.bin"
                    [System.IO.File]::WriteAllBytes($newFile, $value.NewData)
                }
            } catch {
                Write-Warning "Could not save binary file $binaryIndex : $_"
            }
            
            $binaryIndex++
        }
    }
    
    if ($hasBinaryChanges) {
        Write-Host "Binary data saved to: $binaryFolder" -ForegroundColor Green
        Write-Host "  (See 00_FileMapping.txt for key/value details)" -ForegroundColor Gray
    }
    
    return $reportFile
}

# Main execution
Clear-Host
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Registry Change Analyzer" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Scope: $Scope" -ForegroundColor White
Write-Host "Output: $OutputFolder" -ForegroundColor Gray
Write-Host ""

if ($allExclusions.Count -gt 0) {
    Write-Host "Excluded paths: $($allExclusions.Count)" -ForegroundColor Gray
}
Write-Host ""

# Capture BEFORE snapshot
$beforeSnapshot = Get-RegistrySnapshot -RootPaths $scopePaths -SnapshotName "BEFORE snapshot"

# Save snapshot to file
$beforeFile = Join-Path $OutputFolder "Snapshot_Before_$timestamp.xml"
$beforeSnapshot | Export-Clixml -Path $beforeFile -Depth 10
Write-Host "  Snapshot saved: $beforeFile" -ForegroundColor Gray

Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  MAKE YOUR CHANGES NOW" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "The BEFORE snapshot has been captured." -ForegroundColor White
Write-Host ""
Write-Host "Now:" -ForegroundColor Cyan
Write-Host "  1. Make the configuration changes you want to track" -ForegroundColor White
Write-Host "  2. Complete all dialogs and save all settings" -ForegroundColor White
Write-Host "  3. Wait a few seconds for changes to write to registry" -ForegroundColor White
Write-Host ""
Write-Host "Examples:" -ForegroundColor Gray
Write-Host "  - Change printer settings and click OK" -ForegroundColor DarkGray
Write-Host "  - Install/uninstall software" -ForegroundColor DarkGray
Write-Host "  - Modify system settings" -ForegroundColor DarkGray
Write-Host "  - Configure application preferences" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Press ENTER when you're ready to capture the AFTER snapshot..." -ForegroundColor Green
Read-Host

# Capture AFTER snapshot
$afterSnapshot = Get-RegistrySnapshot -RootPaths $scopePaths -SnapshotName "AFTER snapshot"

# Save snapshot to file
$afterFile = Join-Path $OutputFolder "Snapshot_After_$timestamp.xml"
$afterSnapshot | Export-Clixml -Path $afterFile -Depth 10
Write-Host "  Snapshot saved: $afterFile" -ForegroundColor Gray

# Calculate time between snapshots
$timeBetween = $afterSnapshot.Timestamp - $beforeSnapshot.Timestamp

# Compare snapshots
$changes = Compare-RegistrySnapshots -Before $beforeSnapshot -After $afterSnapshot
$changes.Summary.TimeBetweenSnapshots = "{0:N1} seconds" -f $timeBetween.TotalSeconds

# Display summary
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  ANALYSIS COMPLETE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if ($changes.Summary.TotalChanges -eq 0) {
    Write-Host "NO CHANGES DETECTED!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This could mean:" -ForegroundColor White
    Write-Host "  - No changes were actually made" -ForegroundColor Gray
    Write-Host "  - Changes were made outside the monitored scope" -ForegroundColor Gray
    Write-Host "  - Changes were rolled back or canceled" -ForegroundColor Gray
    Write-Host "  - Changes haven't been written to registry yet (try waiting longer)" -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "CHANGES DETECTED!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor White
    Write-Host "  Keys Added:       $($changes.Summary.KeysAdded)" -ForegroundColor $(if ($changes.Summary.KeysAdded -gt 0) { "Green" } else { "Gray" })
    Write-Host "  Keys Deleted:     $($changes.Summary.KeysDeleted)" -ForegroundColor $(if ($changes.Summary.KeysDeleted -gt 0) { "Red" } else { "Gray" })
    Write-Host "  Values Added:     $($changes.Summary.ValuesAdded)" -ForegroundColor $(if ($changes.Summary.ValuesAdded -gt 0) { "Green" } else { "Gray" })
    Write-Host "  Values Deleted:   $($changes.Summary.ValuesDeleted)" -ForegroundColor $(if ($changes.Summary.ValuesDeleted -gt 0) { "Red" } else { "Gray" })
    Write-Host "  Values Modified:  $($changes.Summary.ValuesModified)" -ForegroundColor $(if ($changes.Summary.ValuesModified -gt 0) { "Yellow" } else { "Gray" })
    Write-Host "  ----------------" -ForegroundColor Gray
    Write-Host "  Total:            $($changes.Summary.TotalChanges)" -ForegroundColor Cyan
    Write-Host ""
    
    # Show preview of changes (limit to avoid clutter)
    if ($changes.KeysAdded.Count -gt 0) {
        Write-Host "Keys Added (showing first 3):" -ForegroundColor Green
        $changes.KeysAdded | Select-Object -First 3 | ForEach-Object {
            Write-Host "  + $_" -ForegroundColor DarkGreen
        }
        if ($changes.KeysAdded.Count -gt 3) {
            Write-Host "  ... and $($changes.KeysAdded.Count - 3) more" -ForegroundColor DarkGray
        }
        Write-Host ""
    }
    
    if ($changes.ValuesModified.Count -gt 0) {
        Write-Host "Values Modified (showing first 3):" -ForegroundColor Yellow
        $changes.ValuesModified | Select-Object -First 3 | ForEach-Object {
            Write-Host "  ~ $($_.Key)\$($_.Name)" -ForegroundColor DarkYellow
            if ($_.OldData -is [byte[]] -and $_.NewData -is [byte[]]) {
                Write-Host "    [Binary data changed: $($_.OldData.Length) bytes -> $($_.NewData.Length) bytes]" -ForegroundColor Gray
            }
        }
        if ($changes.ValuesModified.Count -gt 3) {
            Write-Host "  ... and $($changes.ValuesModified.Count - 3) more" -ForegroundColor DarkGray
        }
        Write-Host ""
    }
    
    # Export detailed reports
    Write-Host "Generating detailed reports..." -ForegroundColor Cyan
    $reportFile = Export-ChangesReport -Changes $changes -OutputPath $OutputFolder
    
    Write-Host ""
    Write-Host "Analysis complete! Files saved to:" -ForegroundColor Cyan
    Write-Host "  $OutputFolder" -ForegroundColor White
}

Write-Host ""
Stop-Transcript | Out-Null
Write-Host "Full log saved to: $logFile" -ForegroundColor Gray
Write-Host ""
Write-Host "Press ENTER to exit..."
Read-Host
```

