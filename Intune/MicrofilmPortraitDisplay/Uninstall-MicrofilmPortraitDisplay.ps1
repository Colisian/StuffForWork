<#
.SYNOPSIS
Restores the monitor Rotation values saved by the microfilm portrait display installer.

.DESCRIPTION
Runs as SYSTEM from an Intune Win32 app PowerShell uninstall script. The script
restores only the Rotation values captured before installation, removes the
detection sentinel, and archives the state JSON and full REG backup for recovery.
Position.cx, Position.cy, and every other graphics value are left unchanged.

.EXAMPLE
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-MicrofilmPortraitDisplay.ps1

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-08-27
Version: 1.0.0
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param()

$ErrorActionPreference = 'Stop'

$script:sentinelSubKey = 'SOFTWARE\UMD Libraries\MicrofilmPortraitDisplay'
$script:dataRoot = Join-Path -Path $env:ProgramData -ChildPath 'UMD Libraries\MicrofilmPortraitDisplay'
$script:backupRoot = Join-Path -Path $script:dataRoot -ChildPath 'Backups'
$script:logPath = Join-Path -Path $script:dataRoot -ChildPath 'Logs\Uninstall-MicrofilmPortraitDisplay.log'
$script:statePath = Join-Path -Path $script:dataRoot -ChildPath 'OriginalRotation.json'

    function Write-MicrofilmLog {
        <#
        .SYNOPSIS
        Writes a timestamped uninstall log entry.

        .PARAMETER Message
        Message to write.

        .PARAMETER Level
        Log severity.

        .NOTES
        Author: Oji / University of Maryland Libraries
        Date: 2026-08-27
        Version: 1.0.0
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

    function Test-Hklm64SubKey {
        <#
        .SYNOPSIS
        Tests whether a subkey exists in the 64-bit HKLM registry view.

        .PARAMETER SubKey
        Registry subkey below HKEY_LOCAL_MACHINE.

        .NOTES
        Author: Oji / University of Maryland Libraries
        Date: 2026-08-27
        Version: 1.0.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$SubKey
        )

        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
        try {
            $key = $baseKey.OpenSubKey($SubKey, $false)
            if ($key) {
                $key.Dispose()
                return $true
            }
            return $false
        }
        finally {
            $baseKey.Dispose()
        }
    }

    function Set-Hklm64Value {
        <#
        .SYNOPSIS
        Restores a value through the 64-bit HKLM registry view.

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
        Version: 1.0.0
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

        if (-not $PSCmdlet.ShouldProcess("HKLM:\$SubKey\$Name", "Restore registry value to '$Value'")) {
            return
        }

        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
        try {
            $key = $baseKey.OpenSubKey($SubKey, $true)
            if (-not $key) {
                Write-MicrofilmLog -Message "Skipped missing registry key HKLM:\$SubKey; it was not recreated." -Level WARN
                return
            }

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

    function Remove-Hklm64SubKey {
        <#
        .SYNOPSIS
        Removes the app detection sentinel from the 64-bit HKLM registry view.

        .PARAMETER SubKey
        Registry subkey below HKEY_LOCAL_MACHINE.

        .NOTES
        Author: Oji / University of Maryland Libraries
        Date: 2026-08-27
        Version: 1.0.0
        #>
        [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
        param(
            [Parameter(Mandatory)]
            [string]$SubKey
        )

        if (-not $PSCmdlet.ShouldProcess("HKLM:\$SubKey", 'Remove detection sentinel')) {
            return
        }

        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
        try {
            $baseKey.DeleteSubKeyTree($SubKey, $false)
        }
        finally {
            $baseKey.Dispose()
        }
    }

    function Move-RotationStateToArchive {
        <#
        .SYNOPSIS
        Archives the original-state JSON after a successful restore.

        .PARAMETER SourcePath
        Current state-file path.

        .NOTES
        Author: Oji / University of Maryland Libraries
        Date: 2026-08-27
        Version: 1.0.0
        #>
        [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
        param(
            [Parameter(Mandatory)]
            [string]$SourcePath
        )

        $destinationPath = Join-Path -Path $script:backupRoot -ChildPath (
            'OriginalRotation-restored-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

        if (-not $PSCmdlet.ShouldProcess($destinationPath, 'Archive restored monitor rotation state')) {
            return
        }

        if (-not (Test-Path -LiteralPath $script:backupRoot)) {
            New-Item -Path $script:backupRoot -ItemType Directory -Force | Out-Null
        }

        Move-Item -LiteralPath $SourcePath -Destination $destinationPath -Force
        Write-MicrofilmLog -Message "Archived restored state to $destinationPath."
    }

    function Uninstall-MicrofilmPortraitDisplay {
        <#
        .SYNOPSIS
        Restores saved monitor rotation values and removes installed state.

        .NOTES
        Author: Oji / University of Maryland Libraries
        Date: 2026-08-27
        Version: 1.0.0
        #>
        [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
        param()

        $sentinelExists = Test-Hklm64SubKey -SubKey $script:sentinelSubKey
        if (-not (Test-Path -LiteralPath $script:statePath -PathType Leaf)) {
            if ($sentinelExists) {
                throw "Detection sentinel exists, but the original-state file is missing: $($script:statePath). Restore from the Backups folder before retrying."
            }

            Write-MicrofilmLog -Message 'No installed state was found; nothing needs to be restored.'
            return
        }

        $state = Get-Content -LiteralPath $script:statePath -Raw | ConvertFrom-Json
        if ([int]$state.SchemaVersion -ne 1 -or @($state.Values).Count -eq 0) {
            throw "The original-state file is invalid or empty: $($script:statePath)."
        }

        foreach ($savedValue in @($state.Values)) {
            $kind = [Microsoft.Win32.RegistryValueKind]([System.Enum]::Parse(
                    [Microsoft.Win32.RegistryValueKind], [string]$savedValue.OriginalKind, $true))
            Set-Hklm64Value -SubKey ([string]$savedValue.RegistrySubKey) `
                -Name 'Rotation' `
                -Value ([int]$savedValue.OriginalValue) `
                -Kind $kind `
                -WhatIf:$WhatIfPreference
            Write-MicrofilmLog -Message "Restored HKLM:\$($savedValue.RegistrySubKey)\Rotation to $($savedValue.OriginalValue)."
        }

        if ($sentinelExists) {
            Remove-Hklm64SubKey -SubKey $script:sentinelSubKey -WhatIf:$WhatIfPreference
        }
        Move-RotationStateToArchive -SourcePath $script:statePath -WhatIf:$WhatIfPreference

        Write-MicrofilmLog -Message 'Original monitor rotation values restored. A Windows restart is required.'
    }

    try {
        Uninstall-MicrofilmPortraitDisplay -WhatIf:$WhatIfPreference
        if ($WhatIfPreference) {
            exit 0
        }

        # Intune should map 3010 to Soft reboot. No restart is forced by this script.
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
