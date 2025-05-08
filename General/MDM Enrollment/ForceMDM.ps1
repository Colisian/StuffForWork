try{
    #Ensure MDM registry path exists
    $mdmKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM'
    if (-not (Test-Path $mdmKey)) {
        New-Item -Path $mdmKey -Force | Out-Null
    }
    # Define required properties for MDM enrollment
    $props = @{
        AutoEnrollMDM = @{Type='DWORD'; Value=1};
        UseAADCredentialType = @{Type='DWORD'; Value=1};
        MDMApplicationID = @{Type='String'; Value=''};
        
    }
    # Retrieve the current MDM enrollment settings
    $exisitng = Get-ItemProperty -Path $mdmKey -ErrorAction SilentlyContinue

    foreach ($name in $props.Keys) {
        $prop = $props[$name]
        $needSet = -not $exisitng -or (-not $exisiting.PSObject.properties.Name.Contains($name))
        if ($name -eq 'MDMApplicationId' -and $existing) {
            $needSet = $needSet -or ($existing.MDMApplicationId -ne '')
        }
        if ($needSet) {
            Set-ItemProperty -Path $mdmKey -Name $name -Value $prop.Value -Type $prop.Type -Force
        }
    }

    # Refresh Group Policy and trigger enrollment task
    gpupdate /force | Out-Null
    Get-ScheduledTask -TaskPath '\Microsoft\Windows\DeviceManagement\EnterpriseMgmt\' |
        Start-ScheduledTask
}
catch {
    Write-Error "Enrollment script failed: $_"
    }
