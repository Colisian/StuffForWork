<#
.SYNOPSIS
Sets matching Windows display configurations to portrait rotation for microfilm workstations.

.DESCRIPTION
Runs as SYSTEM from an Intune Win32 app PowerShell script installer. The script:

1. Finds Rotation values in each matching monitor configuration's 00 and 00\00 keys.
2. Exports the complete GraphicsDrivers\Configuration key before making changes.
3. Saves each original Rotation value so uninstall can restore it precisely.
4. Sets each matching Rotation value to 2 (90 degrees clockwise / portrait).
5. Finds USB-class devices whose names contain USB 3.x and disables any enabled
   Device Manager power-management or wake option exposed by Windows.
6. Writes a state-based detection sentinel under 64-bit HKLM\SOFTWARE.

The default MonitorKeyPattern of * is intended for dedicated, single-display
microfilm workstations. If a workstation has other displays that must remain in
landscape mode, replace the default with a monitor-key wildcard identified on a
pilot device before uploading the script to Intune.

.PARAMETER MonitorKeyPattern
Wildcard applied to the immediate child-key names below
GraphicsDrivers\Configuration. Intune's native script upload uses the default
embedded in this file.

.EXAMPLE
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-MicrofilmPortraitDisplay.ps1

.EXAMPLE
.\Install-MicrofilmPortraitDisplay.ps1 -MonitorKeyPattern 'DEL40A8*' -WhatIf

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-08-27
Version: 1.1.0
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$MonitorKeyPattern = '*'
)

$ErrorActionPreference = 'Stop'

$script:appVersion = '1.1.0'
$script:desiredRotation = 2
$script:configurationSubKey = 'SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration'
$script:sentinelSubKey = 'SOFTWARE\UMD Libraries\MicrofilmPortraitDisplay'
$script:dataRoot = Join-Path -Path $env:ProgramData -ChildPath 'UMD Libraries\MicrofilmPortraitDisplay'
$script:backupRoot = Join-Path -Path $script:dataRoot -ChildPath 'Backups'
$script:logPath = Join-Path -Path $script:dataRoot -ChildPath 'Logs\Install-MicrofilmPortraitDisplay.log'
$script:statePath = Join-Path -Path $script:dataRoot -ChildPath 'OriginalRotation.json'

    function Write-MicrofilmLog {
        <#
        .SYNOPSIS
        Writes a timestamped deployment log entry.

        .PARAMETER Message
        Message to write.

        .PARAMETER Level
        Log severity.

        .NOTES
        Author: Oji / University of Maryland Libraries
        Date: 2026-08-27
        Version: 1.1.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Message,

            [Parameter()]
            [ValidateSet('INFO', 'WARN', 'ERROR')]
            [string]$Level = 'INFO'
        )

        $entry = '[{0}][{1}] {2}' -f (Get-Date).ToString('s'), $Level, $Message
        Write-Host $entry

        if (-not $WhatIfPreference) {
            $logDirectory = Split-Path -Path $script:logPath -Parent
            if (-not (Test-Path -LiteralPath $logDirectory)) {
                New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
            }
            Add-Content -LiteralPath $script:logPath -Value $entry -Encoding UTF8
        }
    }

    function Get-RotationTarget {
        <#
        .SYNOPSIS
        Returns matching Rotation values from the graphics configuration registry tree.

        .PARAMETER KeyPattern
        Wildcard used to select monitor-specific configuration keys.

        .NOTES
        Author: Oji / University of Maryland Libraries
        Date: 2026-08-27
        Version: 1.1.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$KeyPattern
        )

        $targets = [System.Collections.Generic.List[object]]::new()
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
        try {
            $configurationKey = $baseKey.OpenSubKey($script:configurationSubKey, $false)
            if (-not $configurationKey) {
                throw "Graphics configuration registry key was not found: HKLM:\$($script:configurationSubKey)"
            }

            try {
                foreach ($monitorKeyName in $configurationKey.GetSubKeyNames() | Where-Object { $_ -like $KeyPattern }) {
                    foreach ($relativeLeaf in '00', '00\00') {
                        $relativeSubKey = "$monitorKeyName\$relativeLeaf"
                        $leafKey = $configurationKey.OpenSubKey($relativeSubKey, $false)
                        if (-not $leafKey) {
                            continue
                        }

                        try {
                            if ($leafKey.GetValueNames() -notcontains 'Rotation') {
                                continue
                            }

                            $targets.Add([pscustomobject]@{
                                    RegistrySubKey = "$($script:configurationSubKey)\$relativeSubKey"
                                    MonitorKey     = $monitorKeyName
                                    RelativeLeaf   = $relativeLeaf
                                    CurrentValue   = [int]$leafKey.GetValue('Rotation')
                                    OriginalKind   = [string]$leafKey.GetValueKind('Rotation')
                                })
                        }
                        finally {
                            $leafKey.Dispose()
                        }
                    }
                }
            }
            finally {
                $configurationKey.Dispose()
            }
        }
        finally {
            $baseKey.Dispose()
        }

        return $targets
    }

    function Export-GraphicsConfiguration {
        <#
        .SYNOPSIS
        Exports the full GraphicsDrivers Configuration key to a timestamped REG file.

        .PARAMETER DestinationPath
        Output path for the registry export.

        .NOTES
        Author: Oji / University of Maryland Libraries
        Date: 2026-08-27
        Version: 1.1.0
        #>
        [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
        param(
            [Parameter(Mandatory)]
            [string]$DestinationPath
        )

        if (-not $PSCmdlet.ShouldProcess($DestinationPath, 'Export graphics configuration registry backup')) {
            return
        }

        if (-not (Test-Path -LiteralPath $script:backupRoot)) {
            New-Item -Path $script:backupRoot -ItemType Directory -Force | Out-Null
        }

        $regExe = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
            Join-Path -Path $env:WINDIR -ChildPath 'Sysnative\reg.exe'
        }
        else {
            Join-Path -Path $env:WINDIR -ChildPath 'System32\reg.exe'
        }

        $nativeKey = "HKLM\$($script:configurationSubKey)"
        & $regExe export $nativeKey $DestinationPath /y | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
            throw "reg.exe could not export $nativeKey (exit code $LASTEXITCODE)."
        }
    }

    function Get-Usb3PowerSetting {
        <#
        .SYNOPSIS
        Returns power-management settings associated with present USB 3.x devices.

        .DESCRIPTION
        Finds USB-class Plug and Play devices whose friendly name contains a
        USB 3.x version, then correlates them to the Device Manager power and
        wake checkboxes exposed through root\wmi.

        .NOTES
        Author: Oji / University of Maryland Libraries
        Date: 2026-08-27
        Version: 1.1.0
        #>
        [CmdletBinding()]
        param()

        $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPClass = 'USB'" |
                Where-Object {
                    $_.Present -ne $false -and
                    $_.Name -match '(?i)\bUSB\s*3(?:\.\d+)+\b'
                })

        $settings = [System.Collections.Generic.List[object]]::new()
        foreach ($settingClass in 'MSPower_DeviceEnable', 'MSPower_DeviceWakeEnable') {
            $classInstances = @(Get-CimInstance -Namespace root\wmi -ClassName $settingClass -ErrorAction SilentlyContinue)
            foreach ($device in $devices) {
                foreach ($classInstance in $classInstances) {
                    $instanceName = [string]$classInstance.InstanceName
                    if (-not $instanceName.StartsWith(
                            [string]$device.PNPDeviceID,
                            [System.StringComparison]::OrdinalIgnoreCase)) {
                        continue
                    }

                    $settings.Add([pscustomobject]@{
                            DeviceName    = [string]$device.Name
                            PnpDeviceId   = [string]$device.PNPDeviceID
                            SettingClass  = $settingClass
                            InstanceName  = $instanceName
                            CurrentEnable = [bool]$classInstance.Enable
                        })
                }
            }
        }

        return $settings
    }

    function Set-Usb3PowerSetting {
        <#
        .SYNOPSIS
        Enables or disables one Device Manager power-management setting.

        .PARAMETER SettingClass
        WMI class holding the power-management setting.

        .PARAMETER InstanceName
        Exact WMI instance name associated with the Plug and Play device.

        .PARAMETER Enable
        Desired checkbox state.

        .NOTES
        Author: Oji / University of Maryland Libraries
        Date: 2026-08-27
        Version: 1.1.0
        #>
        [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
        param(
            [Parameter(Mandatory)]
            [ValidateSet('MSPower_DeviceEnable', 'MSPower_DeviceWakeEnable')]
            [string]$SettingClass,

            [Parameter(Mandatory)]
            [string]$InstanceName,

            [Parameter(Mandatory)]
            [bool]$Enable
        )

        $target = "$SettingClass::$InstanceName"
        if (-not $PSCmdlet.ShouldProcess($target, "Set Device Manager power option to '$Enable'")) {
            return
        }

        $setting = Get-CimInstance -Namespace root\wmi -ClassName $SettingClass |
            Where-Object { $_.InstanceName -eq $InstanceName } |
            Select-Object -First 1
        if (-not $setting) {
            throw "USB power setting disappeared before it could be changed: $target"
        }

        Set-CimInstance -InputObject $setting -Property @{ Enable = $Enable } | Out-Null

        $verified = Get-CimInstance -Namespace root\wmi -ClassName $SettingClass |
            Where-Object { $_.InstanceName -eq $InstanceName } |
            Select-Object -First 1
        if (-not $verified -or [bool]$verified.Enable -ne $Enable) {
            throw "USB power setting verification failed: $target"
        }
    }

    function Save-RotationState {
        <#
        .SYNOPSIS
        Saves original Rotation values for a precise uninstall.

        .PARAMETER State
        State object to serialize.

        .NOTES
        Author: Oji / University of Maryland Libraries
        Date: 2026-08-27
        Version: 1.1.0
        #>
        [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$State
        )

        if (-not $PSCmdlet.ShouldProcess($script:statePath, 'Save original monitor rotation state')) {
            return
        }

        if (-not (Test-Path -LiteralPath $script:dataRoot)) {
            New-Item -Path $script:dataRoot -ItemType Directory -Force | Out-Null
        }

        $State | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $script:statePath -Encoding UTF8 -Force
    }

    function Set-Hklm64Value {
        <#
        .SYNOPSIS
        Writes a value through the 64-bit HKLM registry view.

        .PARAMETER SubKey
        Registry subkey below HKEY_LOCAL_MACHINE.

        .PARAMETER Name
        Registry value name.

        .PARAMETER Value
        Registry value data.

        .PARAMETER Kind
        Registry value kind.

        .NOTES
        Author: Oji / University of Maryland Libraries
        Date: 2026-08-27
        Version: 1.1.0
        #>
        [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
        param(
            [Parameter(Mandatory)]
            [string]$SubKey,

            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [object]$Value,

            [Parameter(Mandatory)]
            [Microsoft.Win32.RegistryValueKind]$Kind
        )

        if (-not $PSCmdlet.ShouldProcess("HKLM:\$SubKey\$Name", "Set registry value to '$Value'")) {
            return
        }

        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
        try {
            $key = $baseKey.CreateSubKey($SubKey)
            try {
                $key.SetValue($Name, $Value, $Kind)
            }
            finally {
                $key.Dispose()
            }
        }
        finally {
            $baseKey.Dispose()
        }
    }

    function Install-MicrofilmPortraitDisplay {
        <#
        .SYNOPSIS
        Backs up, applies, verifies, and records the portrait display configuration.

        .PARAMETER KeyPattern
        Wildcard used to select monitor-specific configuration keys.

        .NOTES
        Author: Oji / University of Maryland Libraries
        Date: 2026-08-27
        Version: 1.1.0
        #>
        [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
        param(
            [Parameter(Mandatory)]
            [string]$KeyPattern
        )

        $targets = @(Get-RotationTarget -KeyPattern $KeyPattern)
        if ($targets.Count -eq 0) {
            throw "No Rotation values were found in matching 00 or 00\00 keys. MonitorKeyPattern: '$KeyPattern'."
        }

        $usbPowerTargets = @(Get-Usb3PowerSetting)
        if ($usbPowerTargets.Count -eq 0) {
            throw 'USB 3.x devices were found with no Device Manager power-management settings, or no present USB 3.x device matched the expected name.'
        }

        Write-MicrofilmLog -Message "Found $($targets.Count) Rotation value(s) matching monitor pattern '$KeyPattern'."
        Write-MicrofilmLog -Message "Found $($usbPowerTargets.Count) power-management setting(s) across USB 3.x devices."

        $backupPath = Join-Path -Path $script:backupRoot -ChildPath (
            'GraphicsDrivers-Configuration-{0}.reg' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Export-GraphicsConfiguration -DestinationPath $backupPath -WhatIf:$WhatIfPreference
        Write-MicrofilmLog -Message "Graphics configuration backup: $backupPath"

        $savedValues = [System.Collections.Generic.List[object]]::new()
        $savedUsbPowerValues = [System.Collections.Generic.List[object]]::new()
        $capturedAtUtc = (Get-Date).ToUniversalTime().ToString('o')

        if (Test-Path -LiteralPath $script:statePath -PathType Leaf) {
            $existingState = Get-Content -LiteralPath $script:statePath -Raw | ConvertFrom-Json
            if ([int]$existingState.SchemaVersion -ne 1) {
                throw "Unsupported state file schema in $($script:statePath)."
            }

            $capturedAtUtc = [string]$existingState.CapturedAtUtc
            foreach ($value in @($existingState.Values)) {
                $savedValues.Add($value)
            }
            if ($existingState.PSObject.Properties['UsbPowerValues']) {
                foreach ($value in @($existingState.UsbPowerValues)) {
                    $savedUsbPowerValues.Add($value)
                }
            }
            Write-MicrofilmLog -Message 'Existing original-state file found; preserved previously captured values.'
        }

        foreach ($target in $targets) {
            $alreadySaved = $savedValues |
                Where-Object { $_.RegistrySubKey -eq $target.RegistrySubKey } |
                Select-Object -First 1
            if (-not $alreadySaved) {
                $savedValues.Add([pscustomobject]@{
                        RegistrySubKey = $target.RegistrySubKey
                        OriginalValue  = $target.CurrentValue
                        OriginalKind   = $target.OriginalKind
                    })
            }
        }

        foreach ($usbPowerTarget in $usbPowerTargets) {
            $alreadySaved = $savedUsbPowerValues |
                Where-Object {
                    $_.SettingClass -eq $usbPowerTarget.SettingClass -and
                    $_.InstanceName -eq $usbPowerTarget.InstanceName
                } |
                Select-Object -First 1
            if (-not $alreadySaved) {
                $savedUsbPowerValues.Add([pscustomobject]@{
                        DeviceName     = $usbPowerTarget.DeviceName
                        PnpDeviceId    = $usbPowerTarget.PnpDeviceId
                        SettingClass   = $usbPowerTarget.SettingClass
                        InstanceName   = $usbPowerTarget.InstanceName
                        OriginalEnable = $usbPowerTarget.CurrentEnable
                    })
            }
        }

        $state = [pscustomobject]@{
            SchemaVersion     = 1
            AppVersion        = $script:appVersion
            CapturedAtUtc     = $capturedAtUtc
            MonitorKeyPattern = $KeyPattern
            Values            = @($savedValues)
            UsbPowerValues    = @($savedUsbPowerValues)
        }
        Save-RotationState -State $state -WhatIf:$WhatIfPreference

        foreach ($target in $targets) {
            Set-Hklm64Value -SubKey $target.RegistrySubKey `
                -Name 'Rotation' `
                -Value $script:desiredRotation `
                -Kind DWord `
                -WhatIf:$WhatIfPreference
            Write-MicrofilmLog -Message "Set HKLM:\$($target.RegistrySubKey)\Rotation from $($target.CurrentValue) to $($script:desiredRotation)."
        }

        foreach ($usbPowerTarget in $usbPowerTargets) {
            if ($usbPowerTarget.CurrentEnable) {
                Set-Usb3PowerSetting -SettingClass $usbPowerTarget.SettingClass `
                    -InstanceName $usbPowerTarget.InstanceName `
                    -Enable $false `
                    -WhatIf:$WhatIfPreference
                Write-MicrofilmLog -Message "Unchecked $($usbPowerTarget.SettingClass) for '$($usbPowerTarget.DeviceName)'."
            }
            else {
                Write-MicrofilmLog -Message "$($usbPowerTarget.SettingClass) was already unchecked for '$($usbPowerTarget.DeviceName)'."
            }
        }

        if (-not $WhatIfPreference) {
            $verificationTargets = @(Get-RotationTarget -KeyPattern $KeyPattern)
            $incorrect = @($verificationTargets | Where-Object { $_.CurrentValue -ne $script:desiredRotation })
            if ($verificationTargets.Count -ne $targets.Count -or $incorrect.Count -gt 0) {
                throw 'Post-install verification found a missing or incorrect Rotation value.'
            }
        }

        Set-Hklm64Value -SubKey $script:sentinelSubKey -Name 'Version' -Value $script:appVersion -Kind String -WhatIf:$WhatIfPreference
        Set-Hklm64Value -SubKey $script:sentinelSubKey -Name 'DesiredRotation' -Value $script:desiredRotation -Kind DWord -WhatIf:$WhatIfPreference
        Set-Hklm64Value -SubKey $script:sentinelSubKey -Name 'TargetCount' -Value $savedValues.Count -Kind DWord -WhatIf:$WhatIfPreference
        Set-Hklm64Value -SubKey $script:sentinelSubKey -Name 'UsbPowerTargetCount' -Value $savedUsbPowerValues.Count -Kind DWord -WhatIf:$WhatIfPreference
        Set-Hklm64Value -SubKey $script:sentinelSubKey -Name 'ConfiguredOnUtc' -Value ((Get-Date).ToUniversalTime().ToString('o')) -Kind String -WhatIf:$WhatIfPreference
        Set-Hklm64Value -SubKey $script:sentinelSubKey -Name 'StateFile' -Value $script:statePath -Kind String -WhatIf:$WhatIfPreference
        Set-Hklm64Value -SubKey $script:sentinelSubKey -Name 'LastBackupFile' -Value $backupPath -Kind String -WhatIf:$WhatIfPreference

        Write-MicrofilmLog -Message "Portrait rotation and USB 3.x power management configured. A Windows restart is required. Version: $($script:appVersion)."
    }

    try {
        Install-MicrofilmPortraitDisplay -KeyPattern $MonitorKeyPattern -WhatIf:$WhatIfPreference
        if ($WhatIfPreference) {
            exit 0
        }

        # Intune should map 3010 to Soft reboot. The script never restarts a patron workstation itself.
        exit 3010
    }
    catch {
        $message = $_.Exception.Message
        try {
            Write-MicrofilmLog -Message $message -Level ERROR
        }
        catch {
            Write-Error -Message $message
        }
        exit 1
    }
