<#
.SYNOPSIS
    Forces Intune MDM auto-enrollment on hybrid Azure AD joined Windows devices.

.DESCRIPTION
    Consolidated replacement for ForceEnroll.ps1 / ForceMDM.ps1. Remediates devices
    that are hybrid Azure AD joined but failed to auto-enroll into Intune.

    Default (non-destructive) behavior:
      1. Verifies elevation and hybrid Azure AD join state.
      2. Sets the machine auto-enrollment policy values (AutoEnrollMDM,
         UseAADCredentialType) under HKLM.
      3. Refreshes computer Group Policy.
      4. Ensures enrollment services are running.
      5. Triggers any existing \Microsoft\Windows\EnterpriseMgmt\* tasks.
      6. Runs DeviceEnroller.exe /c /AutoEnrollMDM immediately, and registers a
         one-shot SYSTEM fallback task 5 minutes out (self-deleting).

    With -CleanStaleEnrollments it first tears down existing Intune enrollment
    artifacts (Enrollments\<GUID> and OMADM account registry keys, the matching
    EnterpriseMgmt\<GUID> task folder, and Intune MDM device certificates) so the
    device re-enrolls cleanly. This is destructive to a working enrollment, so it
    is opt-in and honors -WhatIf.

    Designed to run non-interactively (Intune, remediation, RMM) as SYSTEM or an
    elevated admin. No parameters are required. Exit 0 = success, 1 = failure.

.PARAMETER CleanStaleEnrollments
    Remove existing Intune enrollment registry keys, scheduled task folders, and
    MDM device certificates before re-enrolling. Use for broken/orphaned
    enrollments. Supports -WhatIf.

.PARAMETER SkipJoinCheck
    Proceed even if the device does not report as hybrid Azure AD joined.
    Enrollment will normally fail in that state; intended for testing.

.PARAMETER LogPath
    Full path of the log file. Defaults to
    %ProgramData%\UMDLibraries\Logs\Invoke-MDMAutoEnrollment.log.

.EXAMPLE
    .\Invoke-MDMAutoEnrollment.ps1
    Standard remediation: set policy keys and kick auto-enrollment.

.EXAMPLE
    .\Invoke-MDMAutoEnrollment.ps1 -CleanStaleEnrollments -WhatIf
    Show which enrollment artifacts would be removed, without changing anything.

.EXAMPLE
    .\Invoke-MDMAutoEnrollment.ps1 -CleanStaleEnrollments
    Full re-enrollment: wipe stale enrollment state, then force enrollment.

.NOTES
    Author  : Oji (cmcleod1@umd.edu) — UMD Libraries IT
    Date    : 2026-07-03
    Version : 1.0
    Requires: Run elevated (SYSTEM or local admin). Windows 10/11, PS 5.1+.
    Verify  : dsregcmd /status | Select-String -Pattern 'MDMUrl'
              Get-ScheduledTask -TaskPath '\Microsoft\Windows\EnterpriseMgmt\*'
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$CleanStaleEnrollments,

    [switch]$SkipJoinCheck,

    [string]$LogPath = "$env:ProgramData\UMDLibraries\Logs\Invoke-MDMAutoEnrollment.log"
)

begin {
    $ErrorActionPreference = 'Stop'

    # Intune's MDM enrollment provider ID; used to identify which enrollment
    # GUIDs belong to Intune vs. other management (e.g., co-mgmt artifacts).
    $script:IntuneProviderId = 'MS DM Server'
    $script:EnrollmentsKey   = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
    $script:OmaDmAccountsKey = 'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts'
    $script:MdmPolicyKey     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM'

    function Write-Log {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Message,
            [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
        )
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        # Console output is what Intune captures; file is for on-device forensics.
        Write-Output $line
        try {
            Add-Content -Path $script:LogPath -Value $line -ErrorAction Stop
        } catch {
            # Never let logging kill remediation (e.g., read-only ProgramData redirect)
        }
    }

    function Test-IsElevated {
        [CmdletBinding()]
        param()
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    function Get-HybridJoinState {
        [CmdletBinding()]
        param()
        $dsreg = & "$env:WINDIR\System32\dsregcmd.exe" /status
        [PSCustomObject]@{
            AzureAdJoined = [bool]($dsreg | Select-String 'AzureAdJoined\s*:\s*YES')
            DomainJoined  = [bool]($dsreg | Select-String 'DomainJoined\s*:\s*YES')
            MdmUrlPresent = [bool]($dsreg | Select-String 'MdmUrl\s*:\s*\S')
        }
    }

    function Get-IntuneEnrollment {
        # Returns the enrollment GUID keys whose ProviderID is Intune's.
        # NOTE: no trailing \* on the path — we want the GUID keys themselves,
        # which is where ProviderID/EnrollmentType live.
        [CmdletBinding()]
        param()
        if (-not (Test-Path $script:EnrollmentsKey)) { return @() }
        @(Get-ChildItem -Path $script:EnrollmentsKey | Where-Object {
            $_.PSChildName -match '^[0-9a-fA-F-]{36}$' -and
            $_.GetValue('ProviderID') -eq $script:IntuneProviderId
        })
    }

    function Remove-StaleEnrollment {
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)][string]$EnrollmentId
        )
        # 1. Scheduled task folder \Microsoft\Windows\EnterpriseMgmt\<GUID>
        #    Unregister-ScheduledTask can't delete folders, so use the COM API.
        try {
            $scheduler = New-Object -ComObject 'Schedule.Service'
            $scheduler.Connect()
            $entMgmt = $scheduler.GetFolder('\Microsoft\Windows\EnterpriseMgmt')
            $guidFolder = $entMgmt.GetFolders(0) | Where-Object { $_.Name -eq $EnrollmentId }
            if ($guidFolder) {
                if ($PSCmdlet.ShouldProcess("\Microsoft\Windows\EnterpriseMgmt\$EnrollmentId", 'Delete task folder')) {
                    foreach ($task in $guidFolder.GetTasks(1)) {
                        $guidFolder.DeleteTask($task.Name, 0)
                    }
                    foreach ($sub in $guidFolder.GetFolders(0)) {
                        foreach ($task in $sub.GetTasks(1)) {
                            $sub.DeleteTask($task.Name, 0)
                        }
                        $guidFolder.DeleteFolder($sub.Name, 0)
                    }
                    $entMgmt.DeleteFolder($EnrollmentId, 0)
                    Write-Log "Removed task folder EnterpriseMgmt\$EnrollmentId"
                }
            }
        } catch {
            Write-Log "Could not remove task folder for ${EnrollmentId}: $($_.Exception.Message)" -Level WARN
        }

        # 2. Registry: enrollment key + OMADM account key share the same GUID
        foreach ($base in @($script:EnrollmentsKey, $script:OmaDmAccountsKey)) {
            $key = Join-Path $base $EnrollmentId
            if (Test-Path $key) {
                if ($PSCmdlet.ShouldProcess($key, 'Remove registry key')) {
                    Remove-Item -Path $key -Recurse -Force
                    Write-Log "Removed registry key $key"
                }
            }
        }
    }

    function Remove-IntuneMdmCertificate {
        [CmdletBinding(SupportsShouldProcess)]
        param()
        $certs = @(Get-ChildItem -Path 'Cert:\LocalMachine\My' |
            Where-Object { $_.Issuer -match 'Microsoft Intune MDM Device CA' })
        foreach ($cert in $certs) {
            if ($PSCmdlet.ShouldProcess("$($cert.Subject) ($($cert.Thumbprint))", 'Remove Intune MDM device certificate')) {
                Remove-Item -Path $cert.PSPath -Force
                Write-Log "Removed Intune MDM device certificate $($cert.Thumbprint)"
            }
        }
        if ($certs.Count -eq 0) {
            Write-Log 'No Intune MDM device certificates found.'
        }
    }
}

process {
    try {
        $logDir = Split-Path -Path $LogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        Write-Log '=== Invoke-MDMAutoEnrollment starting ==='

        # --- Preflight -------------------------------------------------------
        if (-not (Test-IsElevated)) {
            Write-Log 'Script must run elevated (SYSTEM or local administrator). Exiting.' -Level ERROR
            exit 1
        }

        $joinState = Get-HybridJoinState
        Write-Log "Join state: AzureAdJoined=$($joinState.AzureAdJoined) DomainJoined=$($joinState.DomainJoined) MdmUrlConfigured=$($joinState.MdmUrlPresent)"
        if (-not ($joinState.AzureAdJoined -and $joinState.DomainJoined)) {
            if ($SkipJoinCheck) {
                Write-Log 'Device is NOT hybrid Azure AD joined; continuing because -SkipJoinCheck was specified.' -Level WARN
            } else {
                Write-Log 'Device is NOT hybrid Azure AD joined. Auto-enrollment requires hybrid join; fix join state first (check AAD Connect sync / dsregcmd /debug). Exiting.' -Level ERROR
                exit 1
            }
        }

        $existing = Get-IntuneEnrollment
        if ($existing.Count -gt 0) {
            Write-Log "Found $($existing.Count) existing Intune enrollment key(s): $($existing.PSChildName -join ', ')"
        } else {
            Write-Log 'No existing Intune enrollment keys found.'
        }

        # --- Optional teardown of stale enrollment state ---------------------
        if ($CleanStaleEnrollments) {
            if ($existing.Count -eq 0) {
                Write-Log 'CleanStaleEnrollments specified but there is nothing to clean.' -Level WARN
            }
            foreach ($enrollment in $existing) {
                Remove-StaleEnrollment -EnrollmentId $enrollment.PSChildName
            }
            Remove-IntuneMdmCertificate
        }

        # --- Auto-enrollment policy values ------------------------------------
        if ($PSCmdlet.ShouldProcess($script:MdmPolicyKey, 'Set AutoEnrollMDM / UseAADCredentialType')) {
            if (-not (Test-Path $script:MdmPolicyKey)) {
                New-Item -Path $script:MdmPolicyKey -Force | Out-Null
            }
            Set-ItemProperty -Path $script:MdmPolicyKey -Name 'AutoEnrollMDM' -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $script:MdmPolicyKey -Name 'UseAADCredentialType' -Value 1 -Type DWord -Force
            Write-Log 'Set AutoEnrollMDM=1 and UseAADCredentialType=1 (user credential).'
        }

        # --- Refresh computer policy so the MDM enrollment CSE runs ----------
        if ($PSCmdlet.ShouldProcess('Computer Group Policy', 'gpupdate /force')) {
            & "$env:WINDIR\System32\gpupdate.exe" /target:computer /force | Out-Null
            Write-Log 'Computer Group Policy refreshed.'
        }

        # --- Enrollment services ----------------------------------------------
        # dmwappushservice no longer exists on newer builds; absence is fine.
        foreach ($serviceName in @('DmEnrollmentSvc', 'dmwappushservice')) {
            $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if (-not $svc) {
                Write-Log "Service $serviceName not present on this build (OK)."
                continue
            }
            if ($svc.Status -ne 'Running' -and $svc.StartType -ne 'Disabled') {
                if ($PSCmdlet.ShouldProcess($serviceName, 'Start service')) {
                    try {
                        Start-Service -Name $serviceName
                        Write-Log "Started service $serviceName."
                    } catch {
                        Write-Log "Could not start ${serviceName}: $($_.Exception.Message)" -Level WARN
                    }
                }
            } else {
                Write-Log "Service $serviceName state: $($svc.Status) (StartType: $($svc.StartType))."
            }
        }

        # --- Kick any existing enrollment tasks (GUID subfolders need the *) --
        $entTasks = @(Get-ScheduledTask -TaskPath '\Microsoft\Windows\EnterpriseMgmt\*' -ErrorAction SilentlyContinue)
        if ($entTasks.Count -gt 0) {
            if ($PSCmdlet.ShouldProcess("$($entTasks.Count) EnterpriseMgmt task(s)", 'Start scheduled tasks')) {
                $entTasks | Start-ScheduledTask -ErrorAction SilentlyContinue
                Write-Log "Triggered $($entTasks.Count) existing EnterpriseMgmt task(s)."
            }
        } else {
            Write-Log 'No EnterpriseMgmt tasks present yet (expected if never enrolled or after cleanup).'
        }

        # --- Immediate enrollment attempt -------------------------------------
        $deviceEnroller = "$env:WINDIR\System32\DeviceEnroller.exe"
        if (-not (Test-Path $deviceEnroller)) {
            Write-Log "DeviceEnroller.exe not found at $deviceEnroller — cannot force enrollment on this build." -Level ERROR
            exit 1
        }
        if ($PSCmdlet.ShouldProcess($deviceEnroller, 'Run /c /AutoEnrollMDM')) {
            $proc = Start-Process -FilePath $deviceEnroller -ArgumentList '/c', '/AutoEnrollMDM' `
                        -Wait -WindowStyle Hidden -PassThru
            Write-Log "DeviceEnroller.exe completed with exit code $($proc.ExitCode)."
        }

        # --- Fallback one-shot task (retries after policy has settled) --------
        # DeleteExpiredTaskAfter requires the trigger to carry an EndBoundary,
        # otherwise Register-ScheduledTask fails — set it before registering.
        $taskName = 'UMDLIB-MDMAutoEnroll'
        if ($PSCmdlet.ShouldProcess($taskName, 'Register fallback enrollment task (+5 min)')) {
            Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue |
                Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

            $runTime = (Get-Date).AddMinutes(5)
            $action  = New-ScheduledTaskAction -Execute $deviceEnroller -Argument '/c /AutoEnrollMDM'
            $trigger = New-ScheduledTaskTrigger -Once -At $runTime
            $trigger.EndBoundary = $runTime.AddMinutes(30).ToString('yyyy-MM-dd\THH:mm:ss')
            $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' `
                            -LogonType ServiceAccount -RunLevel Highest
            $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                            -DontStopIfGoingOnBatteries -RunOnlyIfNetworkAvailable `
                            -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15) `
                            -DeleteExpiredTaskAfter (New-TimeSpan -Minutes 1)

            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
                -Principal $principal -Settings $settings -Force | Out-Null
            Write-Log "Registered fallback task '$taskName' for $runTime (self-deletes after expiry)."
        }

        Write-Log '=== Completed. Allow 10-15 minutes, then verify: ==='
        Write-Log "  dsregcmd /status  -> AzureAdPrt / 'MDMUrl' should be populated"
        Write-Log "  Get-ScheduledTask -TaskPath '\Microsoft\Windows\EnterpriseMgmt\*'"
        Write-Log '  Settings > Accounts > Access work or school > Info (sync status)'
        Write-Log '  Event log: Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin'
        exit 0
    } catch {
        Write-Log "FATAL: $($_.Exception.Message)" -Level ERROR
        Write-Log "At: $($_.ScriptStackTrace)" -Level ERROR
        exit 1
    }
}
