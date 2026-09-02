<#
.SYNOPSIS
    LIBR-AdobeInstallerCleanup.ps1
    Remediates orphaned Windows Installer cache files and (optionally)
    uninstalls Adobe Acrobat and Adobe Creative Cloud.

.DESCRIPTION
    This script addresses C:\Windows\Installer growth on fleet machines.

    v1.3.0 IMPORTANT BEHAVIORAL CHANGE:
    Diagnostics (July 2026) proved that the bulk of the directory growth is
    NOT orphaned files — it is legitimately registered cumulative Acrobat
    MSP patches (~856 MB - 1.25 GB each, permanently cached by Windows
    Installer, superseded ones included). Those CANNOT be safely deleted
    from disk; removing them causes "missing .msi/.msp cache" errors on the
    next update, repair, or uninstall. The only supported way to reclaim
    that space is uninstalling/reinstalling Acrobat with a current base
    installer (owned by DIT via Patch My PC).

    Accordingly, this script:
      1. Logs all actions to C:\ProgramData\LIBR\Logs for audit purposes
      2. Reports current C: drive free space and Installer directory size
      3. Identifies GENUINELY orphaned .msi/.msp files using registration
         data from ALL SIDs under Installer\UserData (v1.2.0 only checked
         S-1-5-18 and missed the per-patch LocalPackage key entirely,
         causing registered patches to be misclassified as orphaned)
      4. Removes orphaned files older than -MinFileAgeDays (default 2) —
         the age guard protects in-flight installations whose cache file
         exists before its registration is written
      5. Reports (but never deletes) registered Adobe MSP accumulation,
         so Intune logs capture fleet-wide numbers for the DIT/PMPC ask
      6. Disables Adobe auto-update (tasks, ARM service, FeatureLockDown)
      7. [Unless -CleanOnly] Uninstalls Adobe Acrobat and Creative Cloud
         and cleans Adobe profile/shared directories
      8. Reports recovered disk space

.PARAMETER LogPath
    Path to the log directory. Default: C:\ProgramData\LIBR\Logs

.PARAMETER CleanOnly
    Perform cleanup and updater-disable only; skip all Adobe uninstall and
    profile-removal steps. Used by the "LIBR - Adobe Installer Cleanup"
    Win32 app (Install-CleanOnly.cmd). Writes a distinct detection flag:
    AdobeInstallerCleanup-CleanOnly.flag

.PARAMETER MinFileAgeDays
    Minimum age (by CreationTime) before an unregistered file is treated
    as orphaned. Default: 2. Protects installs in progress.

.NOTES
    Deployment: Intune Win32 App via Company Portal
    Run As:     System (requires admin privileges)
    Author:     UMD Libraries IT
    Version:    1.3.1
    Date:       2026-07-17

    Detection Rules (for Intune):
      Full mode : File exists: C:\ProgramData\LIBR\Logs\AdobeInstallerCleanup.flag
      CleanOnly : File exists: C:\ProgramData\LIBR\Logs\AdobeInstallerCleanup-CleanOnly.flag

    Requirements:
      - Must run as SYSTEM or local Administrator
      - PowerShell 5.1+ (compatible with 7.x)

    CHANGELOG
      1.3.1 - Fixed Adobe MSP attribution: patch registry keys often lack a
              DisplayName, so vendor attribution now flows from the owning
              product's Patches subkey association. Added total registered
              MSP reporting as an attribution-independent fallback.
            - CleanOnly mode now disables ONLY update-related Adobe tasks;
              CC runtime tasks (CCXProcess, GCInvoker, Genuine-Integrity,
              AppRegistration) are left alone on live installs. Full mode
              still disables all Adobe tasks.
      1.3.0 - Corrected orphan detection: enumerate every SID under
              Installer\UserData; read LocalPackage from BOTH
              Products\<code>\InstallProperties AND the per-SID Patches\<guid>
              keys (the latter was missing in 1.2.0 - registered MSPs were
              being counted as orphaned).
            - Added case-insensitive HashSet comparison for path matching.
            - Added -MinFileAgeDays in-flight-install guard.
            - Added abort-on-empty-registration sanity check (a registry
              read failure must never result in mass deletion).
            - Added registered-Adobe-MSP size reporting (visibility only).
            - Added -CleanOnly switch so one script serves both Win32 apps.
      1.2.0 - Prior release.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$LogPath = "C:\ProgramData\LIBR\Logs",
    [switch]$CleanOnly,
    [int]$MinFileAgeDays = 2
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Stop"
$ScriptVersion = "1.3.1"
$FlagName = if ($CleanOnly) { "AdobeInstallerCleanup-CleanOnly.flag" } else { "AdobeInstallerCleanup.flag" }
$FlagFile = Join-Path $LogPath $FlagName
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

if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

Write-Log "=============================================="
Write-Log "LIBR Adobe Installer Cleanup v$ScriptVersion"
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "User Context: $env:USERNAME"
Write-Log "Mode: $(if ($CleanOnly) { 'CLEAN-ONLY (no uninstall)' } else { 'FULL (cleanup + uninstall)' })"
Write-Log "Min orphan file age: $MinFileAgeDays day(s)"
Write-Log "WhatIf: $($WhatIfPreference)"
Write-Log "=============================================="

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
Write-Log "C: Drive - Free: $freeGB GB | Used: $usedGB GB | Total: $totalGB GB"

$installerSize = (Get-ChildItem "C:\Windows\Installer" -Force -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum).Sum
$installerSizeGB = [math]::Round($installerSize / 1GB, 2)
Write-Log "C:\Windows\Installer size: $installerSizeGB GB"

# ============================================================================
# STEP 2: IDENTIFY ORPHANED INSTALLER FILES  (v1.3.0 corrected logic)
# ============================================================================

Write-Log "--- STEP 2: Identifying Orphaned Files ---"

try {
    # Registered cache paths, case-insensitive for reliable matching
    $registered = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)

    # Track Adobe-registered MSPs separately for reporting (never deleted)
    $adobeMspBytes = 0
    $adobeMspCount = 0

    $userDataRoot = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData"

    # Enumerate EVERY SID (S-1-5-18 machine context + any per-user/managed
    # installs). v1.2.0 only looked at S-1-5-18 and would orphan-classify
    # per-user installed products.
    # Squished patch GUIDs owned by Adobe products (for vendor attribution).
    # Patch keys themselves often carry no DisplayName, so attribution must
    # come from the owning product's Patches subkey association (v1.3.1 fix).
    $adobePatchGuids = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $registeredMspBytes = 0
    $registeredMspCount = 0

    foreach ($sidKey in (Get-ChildItem $userDataRoot -ErrorAction SilentlyContinue)) {

        # (a) Product MSI caches: UserData\<SID>\Products\<code>\InstallProperties
        Get-ChildItem (Join-Path $sidKey.PSPath "Products") -ErrorAction SilentlyContinue |
            ForEach-Object {
                $ip = Get-ItemProperty (Join-Path $_.PSPath "InstallProperties") -ErrorAction SilentlyContinue
                if ($ip.LocalPackage) { [void]$registered.Add($ip.LocalPackage) }

                # Collect this product's applied-patch GUIDs if it's Adobe
                if ($ip.DisplayName -match "Adobe|Acrobat") {
                    Get-ChildItem (Join-Path $_.PSPath "Patches") -ErrorAction SilentlyContinue |
                        ForEach-Object { [void]$adobePatchGuids.Add($_.PSChildName) }
                }
            }

        # (b) Patch MSP caches: UserData\<SID>\Patches\<squishedGuid>
        #     THIS is where patch LocalPackage lives. v1.2.0 missed this key
        #     entirely, so every registered MSP (incl. ~20 cumulative Adobe
        #     Acrobat patches per machine) was misclassified as orphaned.
        Get-ChildItem (Join-Path $sidKey.PSPath "Patches") -ErrorAction SilentlyContinue |
            ForEach-Object {
                $pp = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if ($pp.LocalPackage) {
                    [void]$registered.Add($pp.LocalPackage)
                    $mspFile = Get-Item $pp.LocalPackage -Force -ErrorAction SilentlyContinue
                    if ($mspFile) {
                        $registeredMspBytes += $mspFile.Length
                        $registeredMspCount++
                        if ($adobePatchGuids.Contains($_.PSChildName)) {
                            $adobeMspBytes += $mspFile.Length
                            $adobeMspCount++
                        }
                    }
                }
            }
    }

    # SANITY CHECK: a failed/empty registry read must NEVER cascade into
    # mass deletion of the entire Installer cache. Any Windows machine has
    # dozens of registered packages; near-zero means something went wrong.
    if ($registered.Count -lt 5) {
        Write-Log "Only $($registered.Count) registered packages found - registry enumeration looks wrong. Aborting cleanup for safety." -Level ERROR
        exit 1
    }

    # Only target .msi and .msp specifically - avoid .mst (transforms) and
    # other extensions that may be referenced indirectly by active products
    $msiFiles = Get-ChildItem "C:\Windows\Installer" -Filter "*.msi" -Force -ErrorAction SilentlyContinue
    $mspFiles = Get-ChildItem "C:\Windows\Installer" -Filter "*.msp" -Force -ErrorAction SilentlyContinue
    $allFiles = @($msiFiles) + @($mspFiles)

    $ageCutoff = (Get-Date).AddDays(-$MinFileAgeDays)

    $orphaned = @($allFiles | Where-Object {
        (-not $registered.Contains($_.FullName)) -and
        ($_.CreationTime -lt $ageCutoff)           # in-flight install guard
    })
    $skippedYoung = @($allFiles | Where-Object {
        (-not $registered.Contains($_.FullName)) -and
        ($_.CreationTime -ge $ageCutoff)
    })

    $orphanedSizeGB = [math]::Round(($orphaned | Measure-Object Length -Sum).Sum / 1GB, 2)
    $adobeMspGB = [math]::Round($adobeMspBytes / 1GB, 2)
    $registeredMspGB = [math]::Round($registeredMspBytes / 1GB, 2)

    Write-Log "Total installer files on disk : $($allFiles.Count)"
    Write-Log "Registered (active, keeping)  : $($registered.Count)"
    Write-Log "Orphaned (safe to remove)     : $($orphaned.Count)"
    Write-Log "Orphaned size                 : $orphanedSizeGB GB"
    if ($skippedYoung.Count -gt 0) {
        Write-Log "Unregistered but < $MinFileAgeDays day(s) old (skipped, possible in-flight install): $($skippedYoung.Count)" -Level WARN
    }
    # Visibility-only metrics for the DIT / Patch My PC conversation:
    Write-Log "REGISTERED MSP cache (all)    : $registeredMspCount patches / $registeredMspGB GB"
    Write-Log "REGISTERED Adobe MSP cache    : $adobeMspCount patches / $adobeMspGB GB (NOT removable by this script - reclaim requires Acrobat reinstall via PMPC)" -Level WARN
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
                if ($orphaned.Count -le 50 -or $removedCount % 50 -eq 0) {
                    Write-Log "Removed ($removedCount/$($orphaned.Count)): $($file.Name) - $([math]::Round($fileSize/1MB,0)) MB"
                }
            }
            catch {
                $failedCount++
                Write-Log "FAILED to remove: $($file.Name) - $_" -Level WARN
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
#     CleanOnly mode leaves Acrobat/CC installed and in active use, so only
#     update-related tasks are touched (disabling CCXProcess, GCInvoker, or
#     Genuine-Integrity tasks on a live CC install can break CC features or
#     trigger genuine-software nags). Full mode disables everything Adobe
#     since the products are being removed anyway.
$taskPattern = if ($CleanOnly) { "Adobe.*Update" } else { "Adobe" }
Write-Log "Task scope pattern: '$taskPattern'"

$adobeTasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName -match $taskPattern -and $_.State -ne "Disabled" }

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

# 4c. Set registry policy to disable Adobe Acrobat auto-updates.
#     FeatureLockDown\bUpdater=0 is the only mechanism Adobe's own updates
#     respect and will not silently revert. NOTE: coordinate with DIT -
#     Patch My PC's "disable vendor self-update" option for Acrobat sets
#     this same policy from the package side, which is the preferred
#     long-term owner of this setting.
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
# STEP 5: UNINSTALL ADOBE PRODUCTS  (skipped in -CleanOnly mode)
# ============================================================================

$adobeProducts = $null
$ccUninstallerCount = 0
$profileCleanCount = 0

if ($CleanOnly) {
    Write-Log "--- STEP 5: SKIPPED (CleanOnly mode - Adobe products left installed) ---"
}
else {

    Write-Log "--- STEP 5: Uninstalling Adobe Products ---"

    # ------------------------------------------------------------------------
    # Stop Adobe services and processes that hold file locks
    # ------------------------------------------------------------------------
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

    Start-Sleep -Seconds 2

    # Enumerate Adobe products via the Uninstall registry keys.
    # Avoid Win32_Product - querying it triggers an MSI consistency check /
    # self-repair on every installed product on the machine.
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

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
                    Write-Log "Failed to uninstall $productName - $_" -Level ERROR
                }
            }
        }
    }
    else {
        Write-Log "No Adobe Acrobat products found to uninstall"
    }

    # ------------------------------------------------------------------------
    # STEP 5b: RUN ADOBE CREATIVE CLOUD UNINSTALLER (BACKUP)
    # ------------------------------------------------------------------------
    Write-Log "--- STEP 5b: Adobe Creative Cloud Uninstaller (backup) ---"

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
                    Write-Log "Failed to run Creative Cloud Uninstaller - $_" -Level ERROR
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
                        Write-Log "Failed to remove $fullPath - $_" -Level WARN
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
                    Write-Log "Failed to remove $sharedPath - $_" -Level WARN
                }
            }
        }
    }

} # end if (-not $CleanOnly)

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
Write-Log "Mode                      : $(if ($CleanOnly) { 'CleanOnly' } else { 'Full' })"
Write-Log "Orphaned files removed    : $removedCount"
Write-Log "Failed to remove          : $failedCount"
Write-Log "Disk space recovered      : $recoveredGB GB"
Write-Log "C: free space before      : $freeGB GB"
Write-Log "C: free space after       : $freeAfterGB GB"
Write-Log "Installer dir before      : $installerSizeGB GB"
Write-Log "Installer dir after       : $installerAfterGB GB"
Write-Log "Registered Adobe MSP cache: $adobeMspCount patches / $adobeMspGB GB (reclaim via PMPC reinstall)"
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

$flagContent = @"
Script: LIBR-AdobeInstallerCleanup.ps1
Version: $ScriptVersion
Mode: $(if ($CleanOnly) { 'CleanOnly' } else { 'Full' })
Computer: $env:COMPUTERNAME
RunDate: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
OrphanedFilesRemoved: $removedCount
SpaceRecoveredGB: $recoveredGB
RegisteredAdobeMspGB: $adobeMspGB
AdobeProductsRemoved: $adobeProductCount
RebootRequired: $rebootRequired
"@

Set-Content -Path $FlagFile -Value $flagContent -Force
Write-Log "Detection flag written to: $FlagFile" -Level SUCCESS
Write-Log "Script complete." -Level SUCCESS

exit 0