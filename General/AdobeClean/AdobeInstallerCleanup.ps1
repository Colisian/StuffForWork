<#
.SYNOPSIS
    LIBR-AdobeInstallerCleanup.ps1
    Remediates the fleet-wide Adobe Acrobat orphaned installer issue and
    uninstalls Adobe Acrobat and Adobe Creative Cloud.

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
      7. Uninstalls Adobe Acrobat AND Adobe Creative Cloud products
      8. Cleans Adobe profile directories from all user profiles
         (AppData\Roaming\Adobe, AppData\Local\Adobe, AppData\LocalLow\Adobe)
         and selected shared directories (ProgramData\Adobe and
         Program Files\Adobe\Acrobat DC). Common Files\Adobe is intentionally
         left alone to avoid breaking other Adobe apps that may still be
         installed (Photoshop, Illustrator, etc.).
      9. Reports recovered disk space

.PARAMETER LogPath
    Path to the log directory.
    Default: C:\ProgramData\LIBR\Logs

.NOTES
    Deployment: Intune Win32 App via Company Portal
    Run As:     System (requires admin privileges)
    Author:     UMD Libraries IT
    Version:    1.2.0
    Date:       2026-04-30

    Detection Rule (for Intune):
      File exists: C:\ProgramData\LIBR\Logs\AdobeInstallerCleanup.flag

    Requirements:
      - Must run as SYSTEM or local Administrator
      - PowerShell 5.1+ (compatible with 7.x)
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$LogPath = "C:\ProgramData\LIBR\Logs"
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Stop"
$ScriptVersion = "1.2.0"
$FlagFile = Join-Path $LogPath "AdobeInstallerCleanup.flag"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $LogPath "AdobeInstallerCleanup-$Timestamp.log"
$rebootRequired = $false

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
    Add-Content -Path $LogFile -Value $entry
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

$volBefore = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$freeGB = [math]::Round($volBefore.FreeSpace / 1GB, 2)
$totalGB = [math]::Round($volBefore.Size / 1GB, 2)
$usedGB = [math]::Round(($volBefore.Size - $volBefore.FreeSpace) / 1GB, 2)
Write-Log "C: Drive — Free: $freeGB GB | Used: $usedGB GB | Total: $totalGB GB"

# C:\Windows\Installer is a flat directory — no need to recurse
$installerSize = (Get-ChildItem "C:\Windows\Installer" -Force -ErrorAction SilentlyContinue |
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

    # Only target .msi and .msp specifically — avoid .mst (transforms) and
    # other extensions that may be referenced indirectly by active products
    $msiFiles = Get-ChildItem "C:\Windows\Installer" -Filter "*.msi" -Force -ErrorAction SilentlyContinue
    $mspFiles = Get-ChildItem "C:\Windows\Installer" -Filter "*.msp" -Force -ErrorAction SilentlyContinue
    $allFiles = @($msiFiles) + @($mspFiles)
    $orphaned = @($allFiles | Where-Object { $_.FullName -notin $registered })

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

# ============================================================================
# STEP 3: REMOVE ORPHANED FILES
# ============================================================================

Write-Log "--- STEP 3: Removing Orphaned Files ---"

$removedCount = 0
$removedSize = 0
$failedCount = 0

if ($orphaned.Count -eq 0) {
    Write-Log "No orphaned files found. Nothing to remove."
}
else {
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
# STEP 5: UNINSTALL ADOBE PRODUCTS
# ============================================================================

Write-Log "--- STEP 5: Uninstalling Adobe Products ---"

# ----------------------------------------------------------------------------
# Stop Adobe services and processes that hold file locks
# ----------------------------------------------------------------------------
# Adobe CC services and helper processes routinely keep files open in
# Program Files\Adobe and Common Files\Adobe. If we don't stop them first,
# both msiexec /x and the CC Uninstaller commonly fail with "files in use".

$adobeServicesToStop = @(
    "AGSService",            # Adobe Genuine Software Integrity Service
    "AGMService",            # Adobe Genuine Monitor Service
    "AdobeUpdateService",
    "Adobe Update Service",
    "AdobeARMservice"        # may have been disabled in Step 4 but could still be running
)

foreach ($svcName in $adobeServicesToStop) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        if ($PSCmdlet.ShouldProcess($svcName, "Stop service")) {
            try {
                Stop-Service -Name $svcName -Force -ErrorAction Stop
                Write-Log "Stopped service: $svcName"
            }
            catch {
                Write-Log "Could not stop service ${svcName}: $_" -Level WARN
            }
        }
    }
}

# Process names (no .exe extension — Get-Process strips it)
$adobeProcessesToKill = @(
    "Creative Cloud",
    "Creative Cloud Helper",
    "CCXProcess",
    "CCLibrary",
    "Adobe Desktop Service",
    "AdobeIPCBroker",
    "AdobeUpdateService",
    "AGSService",
    "AGMService",
    "armsvc",
    "Adobe CEF Helper",
    "Acrobat",
    "AcroRd32",
    "AcroCEF"
)

foreach ($procName in $adobeProcessesToKill) {
    $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
    foreach ($proc in $procs) {
        if ($PSCmdlet.ShouldProcess("$procName (PID $($proc.Id))", "Stop process")) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                Write-Log "Killed process: $procName (PID $($proc.Id))"
            }
            catch {
                Write-Log "Could not kill process ${procName}: $_" -Level WARN
            }
        }
    }
}

# Brief pause to let handles release before invoking installers
Start-Sleep -Seconds 2

# Enumerate Adobe products via the Uninstall registry keys.
# Avoid Win32_Product — querying it triggers an MSI consistency check /
# self-repair on every installed product on the machine.
$uninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

# Restrict to MSI-installed products (subkey name is the product GUID)
$adobeProducts = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
    Where-Object {
        $_.DisplayName -match "Adobe Acrobat|LIBR - Adobe Acrobat|Adobe Refresh Manager|Adobe Creative Cloud" -and
        $_.PSChildName -match "^\{[0-9A-Fa-f-]+\}$"
    }

if ($adobeProducts) {
    foreach ($product in $adobeProducts) {
        $productCode = $product.PSChildName
        $productName = $product.DisplayName

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
                    $rebootRequired = $true
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

# ----------------------------------------------------------------------------
# STEP 5b: RUN ADOBE CREATIVE CLOUD UNINSTALLER (BACKUP)
# ----------------------------------------------------------------------------
# Catches CC installs that aren't registered as a removable MSI (common when
# CC was installed/updated by the CC Desktop app rather than a packaged MSI).
# This is Adobe's officially-supported silent uninstaller.

Write-Log "--- STEP 5b: Adobe Creative Cloud Uninstaller (backup) ---"

$ccUninstallerCount = 0
$ccUninstallerPaths = @(
    "$env:ProgramFiles\Adobe\Adobe Creative Cloud\Utils\Creative Cloud Uninstaller.exe",
    "${env:ProgramFiles(x86)}\Adobe\Adobe Creative Cloud\Utils\Creative Cloud Uninstaller.exe"
) | Where-Object { Test-Path $_ }

if ($ccUninstallerPaths) {
    foreach ($ccUninstaller in $ccUninstallerPaths) {
        if ($PSCmdlet.ShouldProcess($ccUninstaller, "Run Creative Cloud Uninstaller")) {
            Write-Log "Running: $ccUninstaller -u"
            try {
                $ccResult = Start-Process -FilePath $ccUninstaller `
                    -ArgumentList "-u" `
                    -Wait -PassThru -NoNewWindow

                if ($ccResult.ExitCode -eq 0) {
                    Write-Log "Creative Cloud Uninstaller succeeded" -Level SUCCESS
                    $ccUninstallerCount++
                }
                elseif ($ccResult.ExitCode -eq 3010) {
                    Write-Log "Creative Cloud Uninstaller succeeded (reboot required)" -Level WARN
                    $ccUninstallerCount++
                    $rebootRequired = $true
                }
                else {
                    Write-Log "Creative Cloud Uninstaller returned exit code: $($ccResult.ExitCode)" -Level WARN
                }
            }
            catch {
                Write-Log "Failed to run Creative Cloud Uninstaller — $_" -Level ERROR
            }
        }
    }
}
else {
    Write-Log "Creative Cloud Uninstaller not found (CC may not be installed, or was installed elsewhere)"
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
foreach ($userProfile in $userProfiles) {
    foreach ($subPath in $adobeSubPaths) {
        $fullPath = Join-Path $userProfile.FullName $subPath
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

# ============================================================================
# STEP 6: POST-CLEANUP REPORT
# ============================================================================

Write-Log "--- STEP 6: Post-Cleanup Report ---"

$volAfter = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$freeAfterGB = [math]::Round($volAfter.FreeSpace / 1GB, 2)
$recoveredGB = [math]::Round($removedSize / 1GB, 2)

$installerAfterSize = (Get-ChildItem "C:\Windows\Installer" -Force -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum).Sum
$installerAfterGB = [math]::Round($installerAfterSize / 1GB, 2)

$adobeProductCount = if ($adobeProducts) { @($adobeProducts).Count } else { 0 }

Write-Log "=============================================="
Write-Log "RESULTS SUMMARY"
Write-Log "=============================================="
Write-Log "Orphaned files removed    : $removedCount"
Write-Log "Failed to remove          : $failedCount"
Write-Log "Disk space recovered      : $recoveredGB GB"
Write-Log "C: free space before      : $freeGB GB"
Write-Log "C: free space after       : $freeAfterGB GB"
Write-Log "Installer dir before      : $installerSizeGB GB"
Write-Log "Installer dir after       : $installerAfterGB GB"
Write-Log "Adobe tasks disabled      : $(if ($adobeTasks) { @($adobeTasks).Count } else { 0 })"
Write-Log "Adobe ARM svc disabled    : $(if ($armService) { 'Yes' } else { 'N/A' })"
Write-Log "Adobe update policy set   : Yes"
Write-Log "Adobe products removed    : $adobeProductCount"
Write-Log "CC Uninstaller runs       : $ccUninstallerCount"
Write-Log "Adobe profile dirs removed: $profileCleanCount"
Write-Log "Reboot required           : $(if ($rebootRequired) { 'YES' } else { 'No' })" -Level $(if ($rebootRequired) { 'WARN' } else { 'INFO' })
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
AdobeProductsRemoved: $adobeProductCount
RebootRequired: $rebootRequired
"@

Set-Content -Path $FlagFile -Value $flagContent -Force
Write-Log "Detection flag written to: $FlagFile" -Level SUCCESS
Write-Log "Script complete." -Level SUCCESS

exit 0
