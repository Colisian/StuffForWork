#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes JWrapper Remote Access / SimpleHelp from Windows endpoints.

.DESCRIPTION
    Detects and removes JWrapper Remote Access (SimpleHelp) software,
    associated firewall rules, scheduled tasks, services, registry keys,
    and installation directories.

    Designed for deployment via Microsoft Intune as a Win32 App or
    PowerShell script. Produces a structured log for SIEM/audit review.

    Threat Context:
    JWrapper/SimpleHelp has been used by ransomware operators as a remote
    access toolkit. It installs as a server-side agent, creates inbound
    firewall rules, and allows persistent remote connections without
    user interaction.

.NOTES
    Author      : UMD Libraries IT
    Version     : 1.1
    Last Updated: 2026-03-19
    Intune Run As: SYSTEM
    Intune 32-bit: No (run as 64-bit)

.OUTPUTS
    Log file: C:\ProgramData\UMDLibrariesIT\Logs\Remove-JWrapperSimpleHelp_<timestamp>.log
    Exit 0   = Clean / Remediated successfully
    Exit 1   = Remediation error (check log)
#>

[CmdletBinding(SupportsShouldProcess)]
param()

begin {
    $ErrorActionPreference = 'Stop'

    # ─────────────────────────────────────────────────────────────────────────
    # CONFIGURATION
    # ─────────────────────────────────────────────────────────────────────────

    $ScriptVersion  = "1.1"
    $ScriptName     = "Remove-JWrapperSimpleHelp"
    $LogDir         = "C:\ProgramData\UMDLibrariesIT\Logs"
    $LogFile        = Join-Path $LogDir "${ScriptName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # Known installation paths (SYSTEM-accessible only — $env:APPDATA and
    # $env:LOCALAPPDATA resolve to the SYSTEM profile, not user profiles)
    $TargetPaths = @(
        "C:\ProgramData\JWrapper-Remote Access",
        "C:\ProgramData\SimpleHelp",
        "C:\Program Files\JWrapper-Remote Access",
        "C:\Program Files (x86)\JWrapper-Remote Access",
        "C:\Program Files\SimpleHelp",
        "C:\Program Files (x86)\SimpleHelp"
    )

    # Known service name patterns
    $ServicePatterns = @(
        "JWrapper*",
        "SimpleHelp*"
    )

    # Known scheduled task name patterns
    $TaskPatterns = @(
        "*JWrapper*",
        "*SimpleHelp*"
    )

    # Known firewall rule name patterns
    $FWRulePatterns = @(
        "*JWrapper*",
        "*SimpleHelp*"
    )

    # Registry uninstall key search strings
    $RegistryUninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    $RegistryNamePatterns = @("JWrapper", "SimpleHelp")

    # Known registry run key paths
    $RunKeyPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    )

    # ─────────────────────────────────────────────────────────────────────────
    # LOGGING
    # ─────────────────────────────────────────────────────────────────────────

    <#
    .SYNOPSIS
        Writes a timestamped log entry to both console and log file.
    #>
    function Write-Log {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Message,

            [ValidateSet("INFO","WARN","ERROR","SUCCESS","ACTION")]
            [string]$Level = "INFO"
        )

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $entry = "[$timestamp] [$Level] $Message"
        Write-Output $entry
        Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
    }

    # ─────────────────────────────────────────────────────────────────────────
    # HELPERS
    # ─────────────────────────────────────────────────────────────────────────

    <#
    .SYNOPSIS
        Terminates any running JWrapper/SimpleHelp processes.
    #>
    function Stop-MatchingProcesses {
        [CmdletBinding()]
        param()

        Write-Log "Searching for running JWrapper/SimpleHelp processes..." "INFO"
        $killed = 0
        Get-Process | Where-Object {
            $_.Path -like "*JWrapper*" -or
            $_.Path -like "*SimpleHelp*" -or
            $_.Name -like "*JWrapper*" -or
            $_.Name -like "*SimpleHelp*"
        } | ForEach-Object {
            Write-Log "Stopping process: $($_.Name) (PID $($_.Id)) at $($_.Path)" "ACTION"
            try {
                $_ | Stop-Process -Force -ErrorAction Stop
                $killed++
            } catch {
                Write-Log "Failed to stop process $($_.Name): $_" "WARN"
            }
        }
        Write-Log "Processes stopped: $killed" "INFO"
    }

    <#
    .SYNOPSIS
        Stops and deletes Windows services matching JWrapper/SimpleHelp patterns.
    #>
    function Remove-MatchingServices {
        [CmdletBinding()]
        param()

        Write-Log "Searching for JWrapper/SimpleHelp services..." "INFO"
        $removed = 0
        foreach ($pattern in $ServicePatterns) {
            Get-Service -Name $pattern -ErrorAction SilentlyContinue | ForEach-Object {
                $svc = $_
                Write-Log "Found service: $($svc.Name) [$($svc.DisplayName)] — Status: $($svc.Status)" "ACTION"
                try {
                    if ($svc.Status -ne 'Stopped') {
                        $svc | Stop-Service -Force -ErrorAction Stop
                        Write-Log "Stopped service: $($svc.Name)" "ACTION"
                    }
                    if ($PSCmdlet.ShouldProcess($svc.Name, "sc.exe delete")) {
                        & sc.exe delete $svc.Name 2>&1 | Out-Null
                        if ($LASTEXITCODE -ne 0) {
                            Write-Log "sc.exe delete returned exit code $LASTEXITCODE for $($svc.Name)" "WARN"
                        } else {
                            Write-Log "Deleted service: $($svc.Name)" "SUCCESS"
                            $removed++
                        }
                    }
                } catch {
                    Write-Log "Failed to remove service $($svc.Name): $_" "ERROR"
                }
            }
        }
        Write-Log "Services removed: $removed" "INFO"
    }

    <#
    .SYNOPSIS
        Unregisters scheduled tasks matching JWrapper/SimpleHelp patterns.
    #>
    function Remove-MatchingScheduledTasks {
        [CmdletBinding()]
        param()

        Write-Log "Searching for JWrapper/SimpleHelp scheduled tasks..." "INFO"
        $removed = 0
        try {
            $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue
            foreach ($pattern in $TaskPatterns) {
                $allTasks | Where-Object { $_.TaskName -like $pattern } | ForEach-Object {
                    Write-Log "Removing scheduled task: $($_.TaskPath)$($_.TaskName)" "ACTION"
                    try {
                        Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction Stop
                        Write-Log "Removed task: $($_.TaskName)" "SUCCESS"
                        $removed++
                    } catch {
                        Write-Log "Failed to remove task $($_.TaskName): $_" "ERROR"
                    }
                }
            }
        } catch {
            Write-Log "Error enumerating scheduled tasks: $_" "WARN"
        }
        Write-Log "Scheduled tasks removed: $removed" "INFO"
    }

    <#
    .SYNOPSIS
        Removes firewall rules matching JWrapper/SimpleHelp patterns.
    #>
    function Remove-MatchingFirewallRules {
        [CmdletBinding()]
        param()

        Write-Log "Searching for JWrapper/SimpleHelp firewall rules..." "INFO"
        $removed = 0
        foreach ($pattern in $FWRulePatterns) {
            try {
                $rules = Get-NetFirewallRule -DisplayName $pattern -ErrorAction SilentlyContinue
                foreach ($rule in $rules) {
                    Write-Log "Removing firewall rule: '$($rule.DisplayName)' [Direction: $($rule.Direction), Action: $($rule.Action)]" "ACTION"
                    Remove-NetFirewallRule -Name $rule.Name -ErrorAction Stop
                    Write-Log "Removed firewall rule: $($rule.DisplayName)" "SUCCESS"
                    $removed++
                }
            } catch {
                Write-Log "Error processing firewall rule pattern '$pattern': $_" "WARN"
            }
        }
        Write-Log "Firewall rules removed: $removed" "INFO"
    }

    <#
    .SYNOPSIS
        Removes registry uninstall keys and Run key entries matching JWrapper/SimpleHelp.
    #>
    function Remove-MatchingRegistryKeys {
        [CmdletBinding()]
        param()

        Write-Log "Searching for JWrapper/SimpleHelp registry uninstall keys..." "INFO"
        $removed = 0
        foreach ($regPath in $RegistryUninstallPaths) {
            if (Test-Path $regPath) {
                Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
                    $key = $_
                    $displayName = (Get-ItemProperty $key.PSPath -Name DisplayName -ErrorAction SilentlyContinue).DisplayName
                    foreach ($pattern in $RegistryNamePatterns) {
                        if ($displayName -like "*$pattern*") {
                            Write-Log "Removing uninstall registry key: $($key.PSPath) [$displayName]" "ACTION"
                            try {
                                Remove-Item $key.PSPath -Recurse -Force -ErrorAction Stop
                                Write-Log "Removed registry key: $($key.PSPath)" "SUCCESS"
                                $removed++
                            } catch {
                                Write-Log "Failed to remove registry key $($key.PSPath): $_" "ERROR"
                            }
                            break
                        }
                    }
                }
            }
        }

        # Check Run keys
        Write-Log "Checking Run keys for JWrapper/SimpleHelp entries..." "INFO"
        foreach ($runPath in $RunKeyPaths) {
            if (Test-Path $runPath) {
                $props = Get-Item $runPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Property
                foreach ($prop in $props) {
                    foreach ($pattern in $RegistryNamePatterns) {
                        if ($prop -like "*$pattern*") {
                            Write-Log "Removing Run key entry: [$runPath] $prop" "ACTION"
                            try {
                                Remove-ItemProperty -Path $runPath -Name $prop -Force -ErrorAction Stop
                                Write-Log "Removed Run key: $prop" "SUCCESS"
                                $removed++
                            } catch {
                                Write-Log "Failed to remove Run key ${prop}: $_" "ERROR"
                            }
                        }
                    }
                }
            }
        }

        Write-Log "Registry entries removed: $removed" "INFO"
    }

    <#
    .SYNOPSIS
        Removes JWrapper/SimpleHelp installation directories from disk.
    .DESCRIPTION
        Attempts Remove-Item first. If files are locked or read-only, falls
        back to a robocopy /MIR trick to empty the directory before deletion.
    #>
    function Remove-MatchingDirectories {
        [CmdletBinding()]
        param()

        Write-Log "Searching for JWrapper/SimpleHelp installation directories..." "INFO"
        $removed = 0
        foreach ($path in $TargetPaths) {
            if (Test-Path $path) {
                Write-Log "Found directory: $path — removing..." "ACTION"
                try {
                    # Force-remove read-only attributes first
                    Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                        ForEach-Object { $_.Attributes = 'Normal' }
                    Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed directory: $path" "SUCCESS"
                    $removed++
                } catch {
                    Write-Log "Failed to remove directory ${path}: $_" "ERROR"
                    # Robocopy mirror trick as fallback for stubborn dirs
                    Write-Log "Attempting robocopy fallback for: $path" "WARN"
                    if ($PSCmdlet.ShouldProcess($path, "robocopy /MIR fallback")) {
                        try {
                            $emptyDir = [System.IO.Path]::GetTempFileName()
                            Remove-Item $emptyDir -Force
                            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
                            & robocopy.exe $emptyDir $path /MIR /NFL /NDL /NJH /NJS /NC /NS | Out-Null
                            Remove-Item $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
                            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                            Write-Log "Robocopy fallback succeeded: $path" "SUCCESS"
                            $removed++
                        } catch {
                            Write-Log "Robocopy fallback also failed for ${path}: $_" "ERROR"
                        }
                    }
                }
            }
        }
        Write-Log "Directories removed: $removed" "INFO"
    }

    <#
    .SYNOPSIS
        Checks whether any JWrapper/SimpleHelp artifacts remain on the system.
    .DESCRIPTION
        Validates all artifact types: directories, services, scheduled tasks,
        firewall rules, and registry keys. Returns $true if any are found.
    #>
    function Test-RemnantsExist {
        [CmdletBinding()]
        param()

        # Check running processes
        $remainingProcs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.Path -like "*JWrapper*" -or
            $_.Path -like "*SimpleHelp*" -or
            $_.Name -like "*JWrapper*" -or
            $_.Name -like "*SimpleHelp*"
        }
        if ($remainingProcs) { return $true }

        # Check directories
        foreach ($path in $TargetPaths) {
            if (Test-Path $path) { return $true }
        }

        # Check services
        foreach ($pattern in $ServicePatterns) {
            if (Get-Service -Name $pattern -ErrorAction SilentlyContinue) { return $true }
        }

        # Check scheduled tasks
        try {
            $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue
            foreach ($pattern in $TaskPatterns) {
                if ($allTasks | Where-Object { $_.TaskName -like $pattern }) { return $true }
            }
        } catch {
            # If we can't enumerate tasks, don't block on it
        }

        # Check firewall rules
        foreach ($pattern in $FWRulePatterns) {
            if (Get-NetFirewallRule -DisplayName $pattern -ErrorAction SilentlyContinue) { return $true }
        }

        # Check registry uninstall keys
        foreach ($regPath in $RegistryUninstallPaths) {
            if (Test-Path $regPath) {
                $match = Get-ChildItem $regPath -ErrorAction SilentlyContinue | Where-Object {
                    $displayName = (Get-ItemProperty $_.PSPath -Name DisplayName -ErrorAction SilentlyContinue).DisplayName
                    foreach ($pattern in $RegistryNamePatterns) {
                        if ($displayName -like "*$pattern*") { return $true }
                    }
                    return $false
                }
                if ($match) { return $true }
            }
        }

        return $false
    }
}

process {
    # ─────────────────────────────────────────────────────────────────────────
    # MAIN
    # ─────────────────────────────────────────────────────────────────────────

    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }

    Write-Log "═══════════════════════════════════════════════════════════════" "INFO"
    Write-Log "$ScriptName v$ScriptVersion — UMD Libraries IT" "INFO"
    Write-Log "Hostname  : $env:COMPUTERNAME" "INFO"
    Write-Log "User      : $env:USERNAME" "INFO"
    Write-Log "Timestamp : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "═══════════════════════════════════════════════════════════════" "INFO"

    $exitCode = 0

    try {
        # Step 1: Kill running processes first
        Stop-MatchingProcesses

        # Step 2: Stop and remove services
        Remove-MatchingServices

        # Step 3: Remove scheduled tasks
        Remove-MatchingScheduledTasks

        # Step 4: Remove firewall rules
        Remove-MatchingFirewallRules

        # Step 5: Clean registry
        Remove-MatchingRegistryKeys

        # Step 6: Remove directories (last — after binaries are no longer locked)
        Remove-MatchingDirectories

        # Step 7: Verify all artifact types
        if (Test-RemnantsExist) {
            Write-Log "WARNING: Some remnants may still exist. Manual review recommended." "WARN"
            $exitCode = 1
        } else {
            Write-Log "Verification passed — no JWrapper/SimpleHelp artifacts detected." "SUCCESS"
        }

    } catch {
        Write-Log "Unhandled exception in main execution: $_" "ERROR"
        $exitCode = 1
    }

    Write-Log "─────────────────────────────────────────────────────────────" "INFO"
    Write-Log "Remediation complete. Exit code: $exitCode" "INFO"
    Write-Log "Log saved to: $LogFile" "INFO"

    exit $exitCode
}
