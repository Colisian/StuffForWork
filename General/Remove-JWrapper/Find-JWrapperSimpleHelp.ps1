#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Discovers all JWrapper and SimpleHelp artifacts on a Windows endpoint.

.DESCRIPTION
    Performs a comprehensive scan for JWrapper Remote Access / SimpleHelp
    artifacts across the filesystem, registry, services, scheduled tasks,
    firewall rules, running processes, and per-user profile directories.

    Outputs a structured report to both console and a log file. Use this
    on a known-infected test machine to identify every detection path
    before building Intune detection/remediation scripts.

    This script is READ-ONLY — it does not modify, stop, or delete anything.

.NOTES
    Author      : UMD Libraries IT
    Version     : 1.0
    Date        : 2026-03-19
    Run As      : Administrator (required for service/task/registry enumeration)

.EXAMPLE
    .\Find-JWrapperSimpleHelp.ps1
    Scans the local machine and writes results to console + log file.

.EXAMPLE
    .\Find-JWrapperSimpleHelp.ps1 | Out-File C:\temp\jwrapper-report.txt
    Pipes console output to a text file.
#>

[CmdletBinding()]
param()

begin {
    $ErrorActionPreference = 'Stop'

    $ScriptVersion = "1.0"
    $ScriptName    = "Find-JWrapperSimpleHelp"
    $LogDir        = "C:\ProgramData\UMDLibrariesIT\Logs"
    $LogFile       = Join-Path $LogDir "${ScriptName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # Search keywords used across all scan types
    $Keywords = @("JWrapper", "SimpleHelp")

    # ─────────────────────────────────────────────────────────────────────────
    # KNOWN FILESYSTEM PATHS
    # ─────────────────────────────────────────────────────────────────────────
    $KnownPaths = @(
        "C:\ProgramData\JWrapper-Remote Access",
        "C:\ProgramData\SimpleHelp",
        "C:\Program Files\JWrapper-Remote Access",
        "C:\Program Files (x86)\JWrapper-Remote Access",
        "C:\Program Files\SimpleHelp",
        "C:\Program Files (x86)\SimpleHelp"
    )

    # Per-user profile subdirectories to check (relative to each user's profile)
    $UserProfileSubPaths = @(
        "AppData\Local\JWrapper-Remote Access",
        "AppData\Local\SimpleHelp",
        "AppData\Roaming\JWrapper-Remote Access",
        "AppData\Roaming\SimpleHelp",
        "Desktop\JWrapper*",
        "Downloads\JWrapper*",
        "Downloads\SimpleHelp*"
    )

    # Temp/common drop locations
    $TempPaths = @(
        "$env:SystemRoot\Temp",
        "$env:TEMP"
    )

    # ─────────────────────────────────────────────────────────────────────────
    # REGISTRY LOCATIONS
    # ─────────────────────────────────────────────────────────────────────────
    $RegistryUninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    $RunKeyPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    )

    $ServiceRegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services"

    # Track totals
    $totalFindings = 0

    # ─────────────────────────────────────────────────────────────────────────
    # LOGGING
    # ─────────────────────────────────────────────────────────────────────────
    function Write-Log {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Message,

            [ValidateSet("INFO","FOUND","SECTION","HEADER")]
            [string]$Level = "INFO"
        )

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $entry = "[$timestamp] [$Level] $Message"
        Write-Output $entry
        Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
    }
}

process {
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }

    Write-Log "═══════════════════════════════════════════════════════════════════" "HEADER"
    Write-Log "$ScriptName v$ScriptVersion — JWrapper/SimpleHelp Discovery Scan" "HEADER"
    Write-Log "Hostname  : $env:COMPUTERNAME" "INFO"
    Write-Log "User      : $env:USERNAME" "INFO"
    Write-Log "Timestamp : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "═══════════════════════════════════════════════════════════════════" "HEADER"

    # ─────────────────────────────────────────────────────────────────────────
    # 1. KNOWN FILESYSTEM PATHS
    # ─────────────────────────────────────────────────────────────────────────
    Write-Log "" "INFO"
    Write-Log "─── [1/9] KNOWN INSTALLATION DIRECTORIES ────────────────────────" "SECTION"

    foreach ($path in $KnownPaths) {
        if (Test-Path $path) {
            $size = (Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            $sizeMB = [math]::Round($size / 1MB, 2)
            $fileCount = (Get-ChildItem -Path $path -Recurse -Force -File -ErrorAction SilentlyContinue).Count
            Write-Log "FOUND: $path ($fileCount files, ${sizeMB} MB)" "FOUND"
            $totalFindings++
        } else {
            Write-Log "  Not present: $path" "INFO"
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # 2. PER-USER PROFILE SCAN
    # ─────────────────────────────────────────────────────────────────────────
    Write-Log "" "INFO"
    Write-Log "─── [2/9] USER PROFILE DIRECTORIES ──────────────────────────────" "SECTION"

    $profileRoot = "C:\Users"
    $userDirs = Get-ChildItem -Path $profileRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }

    foreach ($userDir in $userDirs) {
        foreach ($subPath in $UserProfileSubPaths) {
            $fullPath = Join-Path $userDir.FullName $subPath
            # Resolve wildcards
            $resolved = Get-Item -Path $fullPath -ErrorAction SilentlyContinue
            foreach ($item in $resolved) {
                Write-Log "FOUND: $($item.FullName) (User: $($userDir.Name))" "FOUND"
                $totalFindings++
            }
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # 3. BROAD FILESYSTEM SEARCH (C:\ProgramData, Program Files, Users)
    # ─────────────────────────────────────────────────────────────────────────
    Write-Log "" "INFO"
    Write-Log "─── [3/9] BROAD FILESYSTEM SEARCH (files & folders) ─────────────" "SECTION"
    Write-Log "  Scanning common directories for files/folders matching keywords..." "INFO"

    $searchRoots = @(
        "C:\ProgramData",
        "C:\Program Files",
        "C:\Program Files (x86)",
        $profileRoot
    )

    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($keyword in $Keywords) {
            # Search for matching directories
            Get-ChildItem -Path $root -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$keyword*" } |
                ForEach-Object {
                    Write-Log "FOUND DIR:  $($_.FullName)" "FOUND"
                    $totalFindings++
                }
            # Search for matching files (executables, jars, configs)
            Get-ChildItem -Path $root -File -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$keyword*" } |
                ForEach-Object {
                    Write-Log "FOUND FILE: $($_.FullName) ($([math]::Round($_.Length / 1KB, 1)) KB)" "FOUND"
                    $totalFindings++
                }
        }
    }

    # Check temp directories
    foreach ($tmpPath in $TempPaths) {
        if (-not (Test-Path $tmpPath)) { continue }
        foreach ($keyword in $Keywords) {
            Get-ChildItem -Path $tmpPath -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$keyword*" } |
                ForEach-Object {
                    Write-Log "FOUND TEMP: $($_.FullName)" "FOUND"
                    $totalFindings++
                }
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # 4. RUNNING PROCESSES
    # ─────────────────────────────────────────────────────────────────────────
    Write-Log "" "INFO"
    Write-Log "─── [4/9] RUNNING PROCESSES ─────────────────────────────────────" "SECTION"

    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        $proc = $_
        $matchName = $false
        $matchPath = $false
        foreach ($keyword in $Keywords) {
            if ($proc.Name -like "*$keyword*") { $matchName = $true }
            if ($proc.Path -and $proc.Path -like "*$keyword*") { $matchPath = $true }
        }
        if ($matchName -or $matchPath) {
            Write-Log "FOUND PROCESS: $($proc.Name) (PID $($proc.Id)) Path: $($proc.Path)" "FOUND"
            $totalFindings++
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # 5. WINDOWS SERVICES
    # ─────────────────────────────────────────────────────────────────────────
    Write-Log "" "INFO"
    Write-Log "─── [5/9] WINDOWS SERVICES ──────────────────────────────────────" "SECTION"

    foreach ($keyword in $Keywords) {
        Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like "*$keyword*" -or $_.DisplayName -like "*$keyword*"
        } | ForEach-Object {
            $svc = $_
            # Pull the executable path from the registry for extra detail
            $imagePath = $null
            try {
                $regKey = Join-Path $ServiceRegistryPath $svc.Name
                $imagePath = (Get-ItemProperty -Path $regKey -Name ImagePath -ErrorAction SilentlyContinue).ImagePath
            } catch { }
            Write-Log "FOUND SERVICE: $($svc.Name) | Display: $($svc.DisplayName) | Status: $($svc.Status) | StartType: $($svc.StartType)" "FOUND"
            if ($imagePath) {
                Write-Log "  ImagePath: $imagePath" "FOUND"
            }
            $totalFindings++
        }
    }

    # Also check service registry keys directly (catches hidden/broken services)
    Write-Log "  Checking service registry keys directly..." "INFO"
    if (Test-Path $ServiceRegistryPath) {
        Get-ChildItem $ServiceRegistryPath -ErrorAction SilentlyContinue | ForEach-Object {
            $svcKey = $_
            foreach ($keyword in $Keywords) {
                if ($svcKey.PSChildName -like "*$keyword*") {
                    $imgPath = (Get-ItemProperty $svcKey.PSPath -Name ImagePath -ErrorAction SilentlyContinue).ImagePath
                    Write-Log "FOUND SERVICE REG KEY: $($svcKey.PSPath)" "FOUND"
                    if ($imgPath) {
                        Write-Log "  ImagePath: $imgPath" "FOUND"
                    }
                    $totalFindings++
                }
            }
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # 6. SCHEDULED TASKS
    # ─────────────────────────────────────────────────────────────────────────
    Write-Log "" "INFO"
    Write-Log "─── [6/9] SCHEDULED TASKS ───────────────────────────────────────" "SECTION"

    try {
        $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue
        foreach ($keyword in $Keywords) {
            $allTasks | Where-Object {
                $_.TaskName -like "*$keyword*" -or
                $_.TaskPath -like "*$keyword*"
            } | ForEach-Object {
                $taskInfo = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
                Write-Log "FOUND TASK: $($_.TaskPath)$($_.TaskName) | State: $($_.State)" "FOUND"
                # Show what the task runs
                foreach ($action in $_.Actions) {
                    Write-Log "  Action: $($action.Execute) $($action.Arguments)" "FOUND"
                }
                if ($taskInfo.LastRunTime) {
                    Write-Log "  Last Run: $($taskInfo.LastRunTime)" "INFO"
                }
                $totalFindings++
            }
        }
        # Also check task actions that reference JWrapper/SimpleHelp binaries
        # even if the task name doesn't match
        $allTasks | ForEach-Object {
            $task = $_
            foreach ($action in $task.Actions) {
                foreach ($keyword in $Keywords) {
                    if ($action.Execute -like "*$keyword*" -or $action.Arguments -like "*$keyword*") {
                        Write-Log "FOUND TASK (by action): $($task.TaskPath)$($task.TaskName)" "FOUND"
                        Write-Log "  Action: $($action.Execute) $($action.Arguments)" "FOUND"
                        $totalFindings++
                    }
                }
            }
        }
    } catch {
        Write-Log "  Error enumerating scheduled tasks: $_" "INFO"
    }

    # ─────────────────────────────────────────────────────────────────────────
    # 7. FIREWALL RULES
    # ─────────────────────────────────────────────────────────────────────────
    Write-Log "" "INFO"
    Write-Log "─── [7/9] FIREWALL RULES ────────────────────────────────────────" "SECTION"

    try {
        $allFwRules = Get-NetFirewallRule -ErrorAction SilentlyContinue
        foreach ($keyword in $Keywords) {
            $allFwRules | Where-Object {
                $_.DisplayName -like "*$keyword*" -or $_.Name -like "*$keyword*"
            } | ForEach-Object {
                Write-Log "FOUND FW RULE: $($_.DisplayName) | Direction: $($_.Direction) | Action: $($_.Action) | Enabled: $($_.Enabled)" "FOUND"
                # Get the program path associated with this rule
                try {
                    $appFilter = $_ | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
                    if ($appFilter.Program) {
                        Write-Log "  Program: $($appFilter.Program)" "FOUND"
                    }
                } catch { }
                $totalFindings++
            }
        }
    } catch {
        Write-Log "  Error enumerating firewall rules: $_" "INFO"
    }

    # ─────────────────────────────────────────────────────────────────────────
    # 8. REGISTRY (Uninstall Keys, Run Keys, General Search)
    # ─────────────────────────────────────────────────────────────────────────
    Write-Log "" "INFO"
    Write-Log "─── [8/9] REGISTRY ──────────────────────────────────────────────" "SECTION"

    # Uninstall keys
    Write-Log "  Checking Uninstall registry keys..." "INFO"
    foreach ($regPath in $RegistryUninstallPaths) {
        if (-not (Test-Path $regPath)) { continue }
        Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
            $key = $_
            $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
            $displayName = $props.DisplayName
            $installLocation = $props.InstallLocation
            $uninstallString = $props.UninstallString
            foreach ($keyword in $Keywords) {
                if ($displayName -like "*$keyword*" -or
                    $installLocation -like "*$keyword*" -or
                    $uninstallString -like "*$keyword*") {
                    Write-Log "FOUND UNINSTALL KEY: $($key.PSPath)" "FOUND"
                    Write-Log "  DisplayName     : $displayName" "FOUND"
                    Write-Log "  InstallLocation : $installLocation" "FOUND"
                    Write-Log "  UninstallString : $uninstallString" "FOUND"
                    $totalFindings++
                    break
                }
            }
        }
    }

    # Run keys (auto-start entries)
    Write-Log "  Checking Run keys (auto-start)..." "INFO"
    foreach ($runPath in $RunKeyPaths) {
        if (-not (Test-Path $runPath)) { continue }
        $item = Get-Item $runPath -ErrorAction SilentlyContinue
        foreach ($valueName in $item.Property) {
            $valueData = (Get-ItemProperty $runPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
            foreach ($keyword in $Keywords) {
                if ($valueName -like "*$keyword*" -or $valueData -like "*$keyword*") {
                    Write-Log "FOUND RUN KEY: [$runPath] $valueName = $valueData" "FOUND"
                    $totalFindings++
                }
            }
        }
    }

    # Per-user Run keys (load each user's NTUSER.DAT hive)
    Write-Log "  Checking per-user Run keys via HKU..." "INFO"
    try {
        # Enumerate loaded user hives
        $hkuPath = "Registry::HKEY_USERS"
        Get-ChildItem $hkuPath -ErrorAction SilentlyContinue | ForEach-Object {
            $sid = $_.PSChildName
            # Skip service SIDs and _Classes keys
            if ($sid -like "S-1-5-21-*" -and $sid -notlike "*_Classes") {
                $userRunPath = "$hkuPath\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
                if (Test-Path $userRunPath) {
                    $item = Get-Item $userRunPath -ErrorAction SilentlyContinue
                    foreach ($valueName in $item.Property) {
                        $valueData = (Get-ItemProperty $userRunPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
                        foreach ($keyword in $Keywords) {
                            if ($valueName -like "*$keyword*" -or $valueData -like "*$keyword*") {
                                Write-Log "FOUND USER RUN KEY: [HKU\$sid\...\Run] $valueName = $valueData" "FOUND"
                                $totalFindings++
                            }
                        }
                    }
                }
            }
        }
    } catch {
        Write-Log "  Could not enumerate HKU hives: $_" "INFO"
    }

    # General registry keyword search in common software keys
    Write-Log "  Checking general software registry keys..." "INFO"
    $generalRegPaths = @(
        "HKLM:\SOFTWARE",
        "HKLM:\SOFTWARE\WOW6432Node"
    )
    foreach ($regPath in $generalRegPaths) {
        foreach ($keyword in $Keywords) {
            # Only check top-level keys to keep scan time reasonable
            Get-ChildItem $regPath -ErrorAction SilentlyContinue | Where-Object {
                $_.PSChildName -like "*$keyword*"
            } | ForEach-Object {
                Write-Log "FOUND REG KEY: $($_.PSPath)" "FOUND"
                $totalFindings++
            }
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # 9. STARTUP FOLDERS
    # ─────────────────────────────────────────────────────────────────────────
    Write-Log "" "INFO"
    Write-Log "─── [9/9] STARTUP FOLDERS ───────────────────────────────────────" "SECTION"

    # System-wide startup
    $startupPaths = @(
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    )
    # Per-user startup folders
    foreach ($userDir in $userDirs) {
        $startupPaths += Join-Path $userDir.FullName "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
    }

    foreach ($startupPath in $startupPaths) {
        if (-not (Test-Path $startupPath)) { continue }
        foreach ($keyword in $Keywords) {
            Get-ChildItem -Path $startupPath -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$keyword*" } |
                ForEach-Object {
                    Write-Log "FOUND STARTUP ITEM: $($_.FullName)" "FOUND"
                    $totalFindings++
                }
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # SUMMARY
    # ─────────────────────────────────────────────────────────────────────────
    Write-Log "" "INFO"
    Write-Log "═══════════════════════════════════════════════════════════════════" "HEADER"
    Write-Log "SCAN COMPLETE — Total findings: $totalFindings" "HEADER"
    if ($totalFindings -gt 0) {
        Write-Log "Review FOUND entries above to build detection paths." "INFO"
    } else {
        Write-Log "No JWrapper/SimpleHelp artifacts detected on this machine." "INFO"
    }
    Write-Log "Log saved to: $LogFile" "INFO"
    Write-Log "═══════════════════════════════════════════════════════════════════" "HEADER"
}
