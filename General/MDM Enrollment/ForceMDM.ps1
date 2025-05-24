try {
    # Ensure MDM registry path exists
    $mdmKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM'
    if (-not (Test-Path $mdmKey)) {
        New-Item -Path $mdmKey -Force | Out-Null
    }

    # Define required properties for MDM enrollment
    $props = @{
        AutoEnrollMDM        = @{ Type = 'DWORD';  Value = 1  }
        UseAADCredentialType = @{ Type = 'DWORD';  Value = 1  }
        MDMApplicationId     = @{ Type = 'String'; Value = '' }
    }

    # Retrieve the current MDM enrollment settings
    $existing = Get-ItemProperty -Path $mdmKey -ErrorAction SilentlyContinue

    foreach ($name in $props.Keys) {
        $prop   = $props[$name]
        $needSet = -not $existing -or (-not $existing.PSObject.Properties.Name.Contains($name))
        if ($name -eq 'MDMApplicationId' -and $existing) {
            $needSet = $needSet -or ([string]::IsNullOrEmpty($existing.MDMApplicationId))
        }
        if ($needSet) {
            Set-ItemProperty -Path $mdmKey -Name $name -Value $prop.Value -Type $prop.Type -Force
        }
    }

    # Refresh Group Policy and trigger enrollment task
    gpupdate /force | Out-Null
    Get-ScheduledTask -TaskPath '\Microsoft\Windows\DeviceManagement\EnterpriseMgmt\' |
        Start-ScheduledTask

    ### Setup Scheduled Task to run deviceenroller.exe in 5 minutes
    $RunTime       = (Get-Date).AddMinutes(5)
    $STPrin        = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" `
                        -LogonType S4U -RunLevel Highest
    $Stset         = New-ScheduledTaskSettingsSet `
                        -RunOnlyIfNetworkAvailable `
                        -DontStopOnIdleEnd `
                        -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    $actionUpdate  = New-ScheduledTaskAction `
                        -Execute "$env:WINDIR\System32\DeviceEnroller.exe" `
                        -Argument "/c /AutoEnrollMDM"
    $triggerUpdate = New-ScheduledTaskTrigger -Once -At $RunTime

    Register-ScheduledTask `
        -Trigger $triggerUpdate `
        -Action $actionUpdate `
        -Settings $Stset `
        -TaskName "MDMAutoEnroll" `
        -Principal $STPrin `
        -Force

    $TargetTask = Get-ScheduledTask -TaskName "MDMAutoEnroll"
    $TargetTask.Triggers[0].StartBoundary             = $RunTime.ToString("yyyy-MM-dd'T'HH:mm:ss")
    $TargetTask.Triggers[0].EndBoundary               = $RunTime.AddMinutes(10).ToString("yyyy-MM-dd'T'HH:mm:ss")
    $TargetTask.Settings.DeleteExpiredTaskAfter       = "PT0S"
    $TargetTask | Set-ScheduledTask
}
catch {
    Write-Error "FATAL: An unhandled exception was caught. The script will now exit as failed. $_"
    exit 1
}