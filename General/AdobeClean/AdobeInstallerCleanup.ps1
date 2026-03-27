<#
.SYNOPSIS
    LIBR-AdobeInstallerCleanup.ps1
    Remediates the fleet-wide Adobe Acrobat orphaned installer issue.

.DESCRIPTION
    This script addresses a known issue where Adobe Acrobat's MSI-based update
    mechanism repeatedly downloads ~1 GB patches that fail to install, leaving
    orphaned .msp files in C:\Windows\Installer that consume hundreds of GBs.

    The script performs the following actions:
      1. Logs all actions to C:\ProgramData\LIBR\Logs for audit purposes
      2. Reports current C: drive free space and Installer directory size
      3. Identifies orphaned .msi/.msp files in C:\Windows\Installer
      4. Removes orphaned files (with full logging of each file removed)
      5. Disables Adobe Acrobat Update scheduled tasks
      6. Disables the Adobe ARM (Auto Update) service
      7. Optionally uninstalls Adobe Acrobat products (controlled by parameter)
      8. Optionally cleans Adobe profile directories from all user profiles
         (AppData\Roaming\Adobe, AppData\Local\Adobe, AppData\LocalLow\Adobe)
         and shared directories (ProgramData\Adobe, Common Files\Adobe)
      9. Reports recovered disk space

.PARAMETER UninstallAdobe
    If specified, the script will also uninstall Adobe Acrobat products.
    Default: $false (cleanup and disable updates only)

.PARAMETER LogPath
    Path to the log directory.
    Default: C:\ProgramData\LIBR\Logs

.PARAMETER WhatIf
    If specified, the script will report what it would do without making changes.

.NOTES
    Deployment: Intune Win32 App via Company Portal
    Run As:     System (requires admin privileges)
    Author:     UMD Libraries IT
    Version:    1.1.0
    Date:       2026-03-27

    Detection Rules (for Intune):
      Cleanup Only app  → File exists: C:\ProgramData\LIBR\Logs\AdobeInstallerCleanup-CleanOnly.flag
      Cleanup+Uninstall → File exists: C:\ProgramData\LIBR\Logs\AdobeInstallerCleanup-WithUninstall.flag
    
    Requirements:
      - Must run as SYSTEM or local Administrator
      - PowerShell 5.1+
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$UninstallAdobe,

    [string]$LogPath = "C:\ProgramData\LIBR\Logs"
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Stop"
$ScriptVersion = "1.1.0"
$FlagSuffix = if ($UninstallAdobe) { "WithUninstall" } else { "CleanOnly" }
$FlagFile = Join-Path $LogPath "AdobeInstallerCleanup-$FlagSuffix.flag"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $LogPath "AdobeInstallerCleanup-$Timestamp.log"

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS")]
        [string]$Level = "INFO"
    )
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $LogFile -Value $entry -Force
    switch ($Level) {
        "ERROR"   { Write-Host $entry -ForegroundColor Red }
        "WARN"    { Write-Host $entry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $entry -ForegroundColor Green }
        default   { Write-Host $entry }
    }
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

# Create log directory
if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

Write-Log "=============================================="
Write-Log "LIBR Adobe Installer Cleanup v$ScriptVersion"
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "User Context: $env:USERNAME"
Write-Log "UninstallAdobe: $UninstallAdobe"
Write-Log "WhatIf: $($WhatIfPreference)"
Write-Log "=============================================="

# Verify running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Log "Script must run as Administrator or SYSTEM. Exiting." -Level ERROR
    exit 1
}

# ============================================================================
# STEP 1: REPORT CURRENT STATE
# ============================================================================

Write-Log "--- STEP 1: Current Disk State ---"

$volBefore = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
$freeGB = [math]::Round($volBefore.FreeSpace / 1GB, 2)
$totalGB = [math]::Round($volBefore.Size / 1GB, 2)
$usedGB = [math]::Round(($volBefore.Size - $volBefore.FreeSpace) / 1GB, 2)
Write-Log "C: Drive — Free: $freeGB GB | Used: $usedGB GB | Total: $totalGB GB"

$installerSize = (Get-ChildItem "C:\Windows\Installer" -Recurse -Force -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum).Sum
$installerSizeGB = [math]::Round($installerSize / 1GB, 2)
Write-Log "C:\Windows\Installer size: $installerSizeGB GB"

# ============================================================================
# STEP 2: IDENTIFY ORPHANED INSTALLER FILES
# ============================================================================

Write-Log "--- STEP 2: Identifying Orphaned Files ---"

try {
    $registeredPatches = Get-ChildItem `
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Patches" `
        -ErrorAction SilentlyContinue |
        ForEach-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).LocalPackage } |
        Where-Object { $_ }

    $registeredProducts = Get-ChildItem `
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products" `
        -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).LocalPackage } |
        Where-Object { $_ }

    $registered = ($registeredPatches + $registeredProducts) | Sort-Object -Unique
    $allFiles = Get-ChildItem "C:\Windows\Installer\*.ms*" -Force -ErrorAction SilentlyContinue
    $orphaned = $allFiles | Where-Object { $_.FullName -notin $registered }

    $orphanedSizeGB = [math]::Round(($orphaned | Measure-Object Length -Sum).Sum / 1GB, 2)

    Write-Log "Total installer files on disk : $($allFiles.Count)"
    Write-Log "Registered (active, keeping)  : $($registered.Count)"
    Write-Log "Orphaned (safe to remove)     : $($orphaned.Count)"
    Write-Log "Orphaned size                 : $orphanedSizeGB GB"
}
catch {
    Write-Log "Failed to enumerate installer files: $_" -Level ERROR
    exit 1
}

if ($orphaned.Count -eq 0) {
    Write-Log "No orphaned files found. Skipping cleanup." -Level INFO
}

# ============================================================================
# STEP 3: REMOVE ORPHANED FILES
# ============================================================================

Write-Log "--- STEP 3: Removing Orphaned Files ---"

$removedCount = 0
$removedSize = 0
$failedCount = 0

foreach ($file in $orphaned) {
    if ($PSCmdlet.ShouldProcess($file.FullName, "Remove orphaned installer file")) {
        try {
            $fileSize = $file.Length
            Remove-Item $file.FullName -Force
            $removedCount++
            $removedSize += $fileSize
            # Log every 50th file to avoid massive logs, but log all on small batches
            if ($orphaned.Count -le 50 -or $removedCount % 50 -eq 0) {
                Write-Log "Removed ($removedCount/$($orphaned.Count)): $($file.Name) — $([math]::Round($fileSize/1MB,0)) MB"
            }
        }
        catch {
            $failedCount++
            Write-Log "FAILED to remove: $($file.Name) — $_" -Level WARN
        }
    }
}

$removedSizeGB = [math]::Round($removedSize / 1GB, 2)
Write-Log "Removed $removedCount files ($removedSizeGB GB recovered)" -Level SUCCESS
if ($failedCount -gt 0) {
    Write-Log "$failedCount files could not be removed" -Level WARN
}

# ============================================================================
# STEP 4: DISABLE ADOBE AUTO-UPDATE MECHANISMS
# ============================================================================

Write-Log "--- STEP 4: Disabling Adobe Auto-Update ---"

# 4a. Disable Adobe scheduled tasks
$adobeTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | 
    Where-Object { $_.TaskName -match "Adobe" -and $_.State -ne "Disabled" }

foreach ($task in $adobeTasks) {
    if ($PSCmdlet.ShouldProcess($task.TaskName, "Disable scheduled task")) {
        try {
            Disable-ScheduledTask -TaskName $task.TaskName -ErrorAction Stop | Out-Null
            Write-Log "Disabled task: $($task.TaskName)" -Level SUCCESS
        }
        catch {
            Write-Log "Failed to disable task $($task.TaskName): $_" -Level WARN
        }
    }
}

if (-not $adobeTasks -or $adobeTasks.Count -eq 0) {
    Write-Log "No active Adobe scheduled tasks found (already disabled or absent)"
}

# 4b. Disable Adobe ARM (Auto Update Manager) service
$armService = Get-Service -Name "AdobeARMservice" -ErrorAction SilentlyContinue
if ($armService) {
    if ($PSCmdlet.ShouldProcess("AdobeARMservice", "Stop and disable service")) {
        try {
            if ($armService.Status -eq "Running") {
                Stop-Service -Name "AdobeARMservice" -Force
                Write-Log "Stopped AdobeARMservice"
            }
            Set-Service -Name "AdobeARMservice" -StartupType Disabled
            Write-Log "Disabled AdobeARMservice" -Level SUCCESS
        }
        catch {
            Write-Log "Failed to disable AdobeARMservice: $_" -Level WARN
        }
    }
}
else {
    Write-Log "AdobeARMservice not found on this machine"
}

# 4c. Set registry policy to disable Adobe Acrobat auto-updates
$regPath = "HKLM:\SOFTWARE\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown"
if ($PSCmdlet.ShouldProcess($regPath, "Set bUpdater = 0")) {
    try {
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name "bUpdater" -Value 0 -Type DWord -Force
        Write-Log "Set registry policy: Adobe Acrobat auto-update disabled" -Level SUCCESS
    }
    catch {
        Write-Log "Failed to set Adobe update registry policy: $_" -Level WARN
    }
}

# ============================================================================
# STEP 5: UNINSTALL ADOBE PRODUCTS (OPTIONAL)
# ============================================================================

if ($UninstallAdobe) {
    Write-Log "--- STEP 5: Uninstalling Adobe Products ---"

    # Find Adobe Acrobat MSI product codes
    $adobeProducts = Get-WmiObject Win32_Product -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -match "Adobe Acrobat|LIBR - Adobe Acrobat|Adobe Refresh Manager" }

    if ($adobeProducts) {
        foreach ($product in $adobeProducts) {
            $productCode = $product.IdentifyingNumber
            $productName = $product.Name

            if ($PSCmdlet.ShouldProcess($productName, "Uninstall")) {
                Write-Log "Uninstalling: $productName ($productCode)"
                try {
                    $result = Start-Process -FilePath "msiexec.exe" `
                        -ArgumentList "/x `"$productCode`" /qn /norestart REBOOT=ReallySuppress" `
                        -Wait -PassThru -NoNewWindow
                    
                    if ($result.ExitCode -eq 0) {
                        Write-Log "Successfully uninstalled: $productName" -Level SUCCESS
                    }
                    elseif ($result.ExitCode -eq 3010) {
                        Write-Log "Uninstalled $productName (reboot required)" -Level WARN
                    }
                    else {
                        Write-Log "Uninstall of $productName returned exit code: $($result.ExitCode)" -Level WARN
                    }
                }
                catch {
                    Write-Log "Failed to uninstall $productName — $_" -Level ERROR
                }
            }
        }
    }
    else {
        Write-Log "No Adobe Acrobat products found to uninstall"
    }

    # Clean up Adobe scheduled tasks that may remain after uninstall
    $remainingTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | 
        Where-Object { $_.TaskName -match "Adobe" }
    foreach ($task in $remainingTasks) {
        try {
            Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction Stop
            Write-Log "Removed leftover task: $($task.TaskName)"
        }
        catch {
            Write-Log "Could not remove task $($task.TaskName): $_" -Level WARN
        }
    }

    # Clean up Adobe user profile directories across all user profiles
    Write-Log "Cleaning Adobe profile directories..."
    $userProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @("Public", "Default", "Default User", "All Users") }

    $adobeSubPaths = @(
        "AppData\Roaming\Adobe",
        "AppData\Local\Adobe",
        "AppData\LocalLow\Adobe"
    )

    $profileCleanCount = 0
    foreach ($profile in $userProfiles) {
        foreach ($subPath in $adobeSubPaths) {
            $fullPath = Join-Path $profile.FullName $subPath
            if (Test-Path $fullPath) {
                if ($PSCmdlet.ShouldProcess($fullPath, "Remove Adobe profile directory")) {
                    try {
                        Remove-Item $fullPath -Recurse -Force
                        $profileCleanCount++
                        Write-Log "Removed: $fullPath"
                    }
                    catch {
                        Write-Log "Failed to remove $fullPath — $_" -Level WARN
                    }
                }
            }
        }
    }
    Write-Log "Removed $profileCleanCount Adobe profile directories across $($userProfiles.Count) user profiles" -Level SUCCESS

    # Clean up shared Adobe directories
    # NOTE: Only targeting Acrobat DC specifically under Program Files to avoid
    # breaking Adobe Creative Cloud or other Adobe apps that share Common Files
    $sharedAdobePaths = @(
        "C:\ProgramData\Adobe",
        "C:\Program Files\Adobe\Acrobat DC"
    )

    foreach ($sharedPath in $sharedAdobePaths) {
        if (Test-Path $sharedPath) {
            if ($PSCmdlet.ShouldProcess($sharedPath, "Remove Adobe directory")) {
                try {
                    Remove-Item $sharedPath -Recurse -Force
                    Write-Log "Removed: $sharedPath"
                }
                catch {
                    Write-Log "Failed to remove $sharedPath — $_" -Level WARN
                }
            }
        }
    }
}
else {
    Write-Log "--- STEP 5: Skipped (UninstallAdobe not specified) ---"
}

# ============================================================================
# STEP 6: POST-CLEANUP REPORT
# ============================================================================

Write-Log "--- STEP 6: Post-Cleanup Report ---"

# Use WMI for accurate post-cleanup free space (Get-PSDrive caches values within a session)
$volAfter = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
$freeAfterGB = [math]::Round($volAfter.FreeSpace / 1GB, 2)
$recoveredGB = [math]::Round($removedSize / 1GB, 2)

$installerAfterSize = (Get-ChildItem "C:\Windows\Installer" -Recurse -Force -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum).Sum
$installerAfterGB = [math]::Round($installerAfterSize / 1GB, 2)

Write-Log "=============================================="
Write-Log "RESULTS SUMMARY"
Write-Log "=============================================="
Write-Log "Orphaned files removed  : $removedCount"
Write-Log "Failed to remove        : $failedCount"
Write-Log "Disk space recovered    : $recoveredGB GB"
Write-Log "C: free space before    : $freeGB GB"
Write-Log "C: free space after     : $freeAfterGB GB"
Write-Log "Installer dir before    : $installerSizeGB GB"
Write-Log "Installer dir after     : $installerAfterGB GB"
Write-Log "Adobe tasks disabled    : $(if ($adobeTasks) { $adobeTasks.Count } else { 0 })"
Write-Log "Adobe ARM svc disabled  : $(if ($armService) { 'Yes' } else { 'N/A' })"
Write-Log "Adobe update policy set : Yes"
if ($UninstallAdobe) {
    Write-Log "Adobe products removed  : $(if ($adobeProducts) { $adobeProducts.Count } else { 0 })"
    Write-Log "Adobe profile dirs removed: $profileCleanCount"
}
Write-Log "=============================================="

# ============================================================================
# STEP 7: WRITE DETECTION FLAG
# ============================================================================

# This flag file is used by Intune's detection rule to confirm the script ran
$flagContent = @"
Script: LIBR-AdobeInstallerCleanup.ps1
Version: $ScriptVersion
Computer: $env:COMPUTERNAME
RunDate: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
OrphanedFilesRemoved: $removedCount
SpaceRecoveredGB: $recoveredGB
UninstallAdobe: $UninstallAdobe
"@

Set-Content -Path $FlagFile -Value $flagContent -Force
Write-Log "Detection flag written to: $FlagFile" -Level SUCCESS
Write-Log "Script complete." -Level SUCCESS

exit 0