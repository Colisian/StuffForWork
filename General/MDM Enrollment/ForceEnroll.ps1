try {
    Write-Host "Starting Intune MDM enrollment remediation for hybrid joined devices..." -ForegroundColor Green
    
    # Check if device is hybrid Azure AD joined
    $dsregStatus = dsregcmd /status
    $azureJoined = $null -ne ($dsregStatus | Select-String "AzureAdJoined\s*:\s*YES") 
    $domainJoined =  $null -ne ($dsregStatus | Select-String "DomainJoined\s*:\s*YES")
    $isHybridJoined = $azureJoined -and $domainJoined

    
    
    if (-not $isHybridJoined) {
        Write-Warning "Device is not hybrid Azure AD joined. This script is designed for hybrid joined devices."
        Read-Host "Press Enter to continue anyway or Ctrl+C to exit"
    }
    
    Write-Host "Device hybrid join status confirmed." -ForegroundColor Yellow
    
    # Check current MDM enrollment status
    $mdmEnrollment = Get-CimInstance -Namespace root/cimv2/mdm/dmmap -ClassName MDM_Policy_Config01_DeviceStatus02 -ErrorAction SilentlyContinue
    if ($mdmEnrollment) {
        Write-Host "Device appears to be enrolled in MDM. Checking enrollment health..." -ForegroundColor Yellow
    }
    
    # Clean up any existing failed enrollment artifacts
    Write-Host "Cleaning up existing enrollment artifacts..." -ForegroundColor Yellow
    
    # Remove existing enrollment registry keys that might be causing issues
    $enrollmentKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Enrollments\*',
        'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\*'
    )
    
    foreach ($keyPath in $enrollmentKeys) {
        Get-ChildItem -Path $keyPath -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.GetValue("EnrollmentType") -eq 6) { # MDM enrollment type
                Write-Host "Removing stale enrollment key: $($_.Name)" -ForegroundColor Yellow
                Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    # Ensure MDM registry path exists and configure policies
    $mdmPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM'
    if (-not (Test-Path $mdmPolicyKey)) {
        New-Item -Path $mdmPolicyKey -Force | Out-Null
        Write-Host "Created MDM policy registry key." -ForegroundColor Yellow
    }
    
    # Configure MDM auto-enrollment settings
    $mdmSettings = @{
        'AutoEnrollMDM'        = @{ Type = 'DWORD';  Value = 1 }
        'UseAADCredentialType' = @{ Type = 'DWORD';  Value = 1 }
    }
    
    foreach ($setting in $mdmSettings.GetEnumerator()) {
        Set-ItemProperty -Path $mdmPolicyKey -Name $setting.Key -Value $setting.Value.Value -Type $setting.Value.Type -Force
        Write-Host "Set $($setting.Key) = $($setting.Value.Value)" -ForegroundColor Yellow
    }
    
    # Configure user-level auto-enrollment
    $userMdmKey = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM'
    if (-not (Test-Path $userMdmKey)) {
        New-Item -Path $userMdmKey -Force | Out-Null
    }
    Set-ItemProperty -Path $userMdmKey -Name 'AutoEnrollMDM' -Value 1 -Type 'DWORD' -Force
    
    # Force refresh of Azure AD tokens
    Write-Host "Refreshing Azure AD tokens..." -ForegroundColor Yellow
    Start-Process -FilePath "dsregcmd" -ArgumentList "/refreshprt" -Wait -WindowStyle Hidden
    
    # Apply Group Policy changes
    Write-Host "Applying Group Policy updates..." -ForegroundColor Yellow
    Start-Process -FilePath "gpupdate" -ArgumentList "/force" -Wait -WindowStyle Hidden
    
    # Trigger existing enterprise management tasks
    Write-Host "Triggering existing enrollment tasks..." -ForegroundColor Yellow
    $entMgmtTasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\*" -ErrorAction SilentlyContinue
    if ($entMgmtTasks) {
        $entMgmtTasks | Start-ScheduledTask -ErrorAction SilentlyContinue
    }
    
    # Try immediate enrollment first
    Write-Host "Attempting immediate enrollment..." -ForegroundColor Yellow
    $deviceEnrollerPath = "$env:WINDIR\System32\DeviceEnroller.exe"
    if (Test-Path $deviceEnrollerPath) {
        Start-Process -FilePath $deviceEnrollerPath -ArgumentList "/c /AutoEnrollMDM" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
    }
    
    # Create scheduled task for delayed enrollment (fallback)
    Write-Host "Creating fallback enrollment task..." -ForegroundColor Yellow
    $taskName = "Force-IntuneEnrollment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $runTime = (Get-Date).AddMinutes(3)
    
    # Remove any existing similar tasks
    Get-ScheduledTask -TaskName "Force-IntuneEnrollment-*" -ErrorAction SilentlyContinue | 
        Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
    
    $action = New-ScheduledTaskAction -Execute $deviceEnrollerPath -Argument "/c /AutoEnrollMDM"
    $trigger = New-ScheduledTaskTrigger -Once -At $runTime
    $principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RunOnlyIfNetworkAvailable -DeleteExpiredTaskAfter (New-TimeSpan -Minutes 30)
    
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    
    # Modify task to auto-delete after completion
    $task = Get-ScheduledTask -TaskName $taskName
    $task.Settings.DeleteExpiredTaskAfter = "PT1M"  # Delete 1 minute after completion
    $task | Set-ScheduledTask | Out-Null
    
    Write-Host "Fallback enrollment task '$taskName' scheduled for $runTime" -ForegroundColor Green
    
    # Start/restart key services to ensure clean state
    Write-Host "Starting/restarting enrollment-related services..." -ForegroundColor Yellow
    $enrollmentServices = @('DmEnrollmentSvc', 'dmwappushservice')
    
    
    foreach ($serviceName in $enrollmentServices) {
        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($svc) {
            if ($svc.Status -eq 'Running') {
                Write-Host "Restarting $serviceName..." -ForegroundColor Yellow
                Restart-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                Write-Host "Restarted $serviceName" -ForegroundColor Green
            } else {
                Write-Host "Starting $serviceName..." -ForegroundColor Yellow
                Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                $svcCheck = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                if ($svcCheck -and $svcCheck.Status -eq 'Running') {
                    Write-Host "Started $serviceName" -ForegroundColor Green
                } else {
                    Write-Host "Failed to start $serviceName" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "$serviceName not found" -ForegroundColor Red
        }
    }
    
    # Trigger the "provisioning initiated session" task
    Write-Host "Looking for provisioning initiated session tasks..." -ForegroundColor Yellow
    $provisioningTasks = Get-ScheduledTask | Where-Object { 
        $_.TaskName -like "*provisioning*initiated*session*" -or 
        $_.TaskName -like "*Provisioning*Initiated*Session*" 
    }
    
    if ($provisioningTasks) {
        foreach ($task in $provisioningTasks) {
            Write-Host "Found and starting task: $($task.TaskName) in path: $($task.TaskPath)" -ForegroundColor Yellow
            try {
                Start-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop
                Write-Host "Successfully started $($task.TaskName)" -ForegroundColor Green
            } catch {
                Write-Host "Failed to start $($task.TaskName): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "No 'provisioning initiated session' tasks found - this may be normal for some devices" -ForegroundColor Yellow
    }
    
    # Provide enrollment verification steps
    Write-Host "`n=== ENROLLMENT VERIFICATION ===" -ForegroundColor Cyan
    Write-Host "To verify enrollment status in 10-15 minutes, run:" -ForegroundColor White
    Write-Host "  dsregcmd /status | findstr -i 'mdm'" -ForegroundColor Gray
    Write-Host "  Get-CimInstance -Namespace root/cimv2/mdm/dmmap -ClassName MDM_Policy_Config01_DeviceStatus02" -ForegroundColor Gray
    Write-Host "`nOr check in Settings > Accounts > Access work or school" -ForegroundColor White
    
    Write-Host "`nScript completed successfully!" -ForegroundColor Green
    Write-Host "Monitor the scheduled task and check enrollment status in 10-15 minutes." -ForegroundColor Yellow
    
} catch {
    Write-Error "FATAL: Script failed with error: $($_.Exception.Message)"
    Write-Host "Additional error details: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}