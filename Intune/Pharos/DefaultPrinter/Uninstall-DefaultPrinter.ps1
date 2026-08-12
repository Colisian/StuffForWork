<#
.SYNOPSIS
Removes the machine-wide default printer enforcement installed by
Install-DefaultPrinter.ps1.

.DESCRIPTION
Runs as SYSTEM from an Intune Win32 app. Unregisters the logon task, removes the
staged per-user payload, restores each profile's previous default printer from
the backup written at install time, and clears the detection sentinel.

The print queue itself is left installed - this app only owns the default
printer choice, not the Pharos package that created the queue.

Every step is best-effort: an uninstall must not fail because one profile hive
is locked or a task was already removed by hand.

.EXAMPLE
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-DefaultPrinter.ps1

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-08-12
Version: 1.0.0
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param()

$ErrorActionPreference = 'Stop'

$script:logPath = Join-Path -Path $env:ProgramData -ChildPath 'UMD\Pharos\Logs\DefaultPrinter-Install.log'
$script:payloadRoot = Join-Path -Path $env:ProgramData -ChildPath 'UMD\Pharos'
$script:sentinelPath = 'SOFTWARE\UMD\Pharos\DefaultPrinter'
$script:taskPath = '\UMD\'
$script:taskName = 'Set-DefaultPrinter'
$script:backupSubKey = 'Software\UMD\Pharos\DefaultPrinter'

function Write-DefaultPrinterLog {
    <#
    .SYNOPSIS
    Writes a timestamped entry to the default printer deployment log.

    .PARAMETER Message
    Message to write.

    .PARAMETER Level
    Log severity.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
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

function Remove-Hklm64Key {
    <#
    .SYNOPSIS
    Deletes an HKLM subkey tree through the 64-bit registry view.

    .PARAMETER Path
    Subkey path below HKLM.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not $PSCmdlet.ShouldProcess("HKLM:\$Path", 'Remove registry key')) {
        return
    }

    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $baseKey.DeleteSubKeyTree($Path, $false)
    }
    finally {
        $baseKey.Dispose()
    }
}

function Get-DefaultProfilePath {
    <#
    .SYNOPSIS
    Returns the path to the default user profile directory.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key = $baseKey.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList')
        if ($key) {
            try {
                $default = $key.GetValue('Default')
                if ($default) {
                    return [System.Environment]::ExpandEnvironmentVariables([string]$default)
                }
            }
            finally {
                $key.Dispose()
            }
        }
    }
    finally {
        $baseKey.Dispose()
    }

    return (Join-Path -Path $env:SystemDrive -ChildPath 'Users\Default')
}

function Get-TargetUserHive {
    <#
    .SYNOPSIS
    Returns the user hives that may hold default printer state.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    $hives = [System.Collections.Generic.List[object]]::new()

    $defaultHive = Join-Path -Path (Get-DefaultProfilePath) -ChildPath 'NTUSER.DAT'
    if (Test-Path -LiteralPath $defaultHive -PathType Leaf) {
        $hives.Add([pscustomobject]@{
                Label    = 'Default User'
                Sid      = $null
                HiveFile = $defaultHive
                Loaded   = $false
            })
    }

    # Filter on Special rather than an S-1-5-21 SID pattern: Entra ID joined
    # machines give interactive users S-1-12-1-* SIDs, and a pattern match would
    # silently skip every real profile on those devices.
    $profiles = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Special -and $_.SID -notin 'S-1-5-18', 'S-1-5-19', 'S-1-5-20' }

    foreach ($userProfile in $profiles) {
        $hiveFile = Join-Path -Path $userProfile.LocalPath -ChildPath 'NTUSER.DAT'

        # Both probes are SilentlyContinue: a profile directory whose ACL denies
        # this process throws UnauthorizedAccessException from Test-Path rather
        # than returning false, which would abort the whole run.
        $loaded = Test-Path -LiteralPath "Registry::HKEY_USERS\$($userProfile.SID)" -ErrorAction SilentlyContinue

        if (-not $loaded -and -not (Test-Path -LiteralPath $hiveFile -PathType Leaf -ErrorAction SilentlyContinue)) {
            continue
        }

        $hives.Add([pscustomobject]@{
                Label    = $userProfile.LocalPath
                Sid      = $userProfile.SID
                HiveFile = $hiveFile
                Loaded   = $loaded
            })
    }

    return $hives
}

function Invoke-RegExe {
    <#
    .SYNOPSIS
    Runs reg.exe and returns its exit code and output.

    .DESCRIPTION
    Windows PowerShell 5.1 turns a native command's stderr into ErrorRecords,
    which under $ErrorActionPreference = 'Stop' throws NativeCommandError before
    the caller can inspect the exit code. Dropping to 'Continue' for the
    duration of the call keeps a locked or in-use hive a recoverable warning
    instead of aborting the whole uninstall.

    .PARAMETER Argument
    Arguments passed to reg.exe.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Argument
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & reg.exe @Argument 2>&1 | ForEach-Object { $_.ToString().Trim() }
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output   = (@($output) -join ' ')
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Restore-HiveDefaultPrinter {
    <#
    .SYNOPSIS
    Restores one user hive to the default printer it had before install.

    .DESCRIPTION
    Reads the backup written by Install-DefaultPrinter.ps1. If the profile had
    no default printer beforehand, the Device value is removed rather than left
    pointing at the enforced queue.

    .PARAMETER HiveRoot
    Provider path to the hive root, e.g. Registry::HKEY_USERS\S-1-5-21-...

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$HiveRoot
    )

    $windowsKey = "$HiveRoot\Software\Microsoft\Windows NT\CurrentVersion\Windows"
    $backupKey = "$HiveRoot\$script:backupSubKey"

    if (-not (Test-Path -LiteralPath $backupKey)) {
        return 'No backup present; nothing to restore'
    }

    if (-not $PSCmdlet.ShouldProcess($HiveRoot, 'Restore previous default printer')) {
        return 'WhatIf'
    }

    $backup = Get-ItemProperty -LiteralPath $backupKey -ErrorAction SilentlyContinue
    $previousDevice = [string]$backup.PreviousDevice
    $previousMode = [string]$backup.PreviousLegacyDefaultPrinterMode

    if (Test-Path -LiteralPath $windowsKey) {
        if ([string]::IsNullOrWhiteSpace($previousDevice)) {
            Remove-ItemProperty -LiteralPath $windowsKey -Name 'Device' -Force -ErrorAction SilentlyContinue
        }
        else {
            Set-ItemProperty -LiteralPath $windowsKey -Name 'Device' -Value $previousDevice -Force
        }

        if ([string]::IsNullOrWhiteSpace($previousMode)) {
            Remove-ItemProperty -LiteralPath $windowsKey -Name 'LegacyDefaultPrinterMode' -Force -ErrorAction SilentlyContinue
        }
        else {
            New-ItemProperty -LiteralPath $windowsKey -Name 'LegacyDefaultPrinterMode' -Value ([int]$previousMode) -PropertyType DWord -Force | Out-Null
        }
    }

    Remove-Item -LiteralPath $backupKey -Recurse -Force -ErrorAction SilentlyContinue

    # Drop the now-empty UMD\Pharos and UMD containers so uninstall leaves no
    # orphan keys, but only when this app was the sole occupant.
    foreach ($parentKey in @("$HiveRoot\Software\UMD\Pharos", "$HiveRoot\Software\UMD")) {
        $parent = Get-Item -LiteralPath $parentKey -ErrorAction SilentlyContinue
        if ($parent -and $parent.SubKeyCount -eq 0 -and $parent.ValueCount -eq 0) {
            Remove-Item -LiteralPath $parentKey -Force -ErrorAction SilentlyContinue
        }
    }

    if ([string]::IsNullOrWhiteSpace($previousDevice)) {
        return 'Restored (no previous default)'
    }

    return "Restored to '$($previousDevice.Split(',')[0])'"
}

function Invoke-ForEachUserHive {
    <#
    .SYNOPSIS
    Runs a script block against every target user hive, loading and unloading
    offline hives as needed.

    .PARAMETER Action
    Script block receiving the hive provider root as its first argument,
    followed by ArgumentList, and returning a short status string for the log.

    .PARAMETER Operation
    Label used in log messages.

    .PARAMETER ArgumentList
    Extra arguments passed to Action after the hive root.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [Parameter(Mandatory)]
        [string]$Operation,

        [Parameter()]
        [object[]]$ArgumentList = @()
    )

    $index = 0
    foreach ($hive in Get-TargetUserHive) {
        $index++
        $mountName = "UMD_DefaultPrinter_$index"
        $mounted = $false

        if ($hive.Loaded) {
            $hiveRoot = "Registry::HKEY_USERS\$($hive.Sid)"
        }
        else {
            $load = Invoke-RegExe -Argument @('load', "HKU\$mountName", $hive.HiveFile)
            if ($load.ExitCode -ne 0) {
                Write-DefaultPrinterLog -Message "$Operation skipped for '$($hive.Label)': could not load hive ($($load.Output))." -Level WARN
                continue
            }

            $mounted = $true
            $hiveRoot = "Registry::HKEY_USERS\$mountName"
        }

        try {
            $actionArgument = @($hiveRoot) + $ArgumentList
            $status = & $Action @actionArgument
            Write-DefaultPrinterLog -Message "$Operation for '$($hive.Label)': $status"
        }
        catch {
            Write-DefaultPrinterLog -Message "$Operation failed for '$($hive.Label)': $($_.Exception.Message)" -Level WARN
        }
        finally {
            if ($mounted) {
                # The provider keeps handles open; without a collection pass the
                # unload fails with "Access is denied" and the hive stays mounted.
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()

                $unload = $null
                for ($attempt = 1; $attempt -le 5; $attempt++) {
                    $unload = Invoke-RegExe -Argument @('unload', "HKU\$mountName")
                    if ($unload.ExitCode -eq 0) { break }
                    Start-Sleep -Milliseconds 500
                }

                if ($unload.ExitCode -ne 0) {
                    Write-DefaultPrinterLog -Message "Could not unload hive HKU\$mountName for '$($hive.Label)': $($unload.Output)" -Level WARN
                }
            }
        }
    }
}

function Uninstall-DefaultPrinter {
    <#
    .SYNOPSIS
    Removes every artifact created by the default printer install.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param()

    Write-DefaultPrinterLog -Message 'Removing default printer enforcement.'

    $task = Get-ScheduledTask -TaskName $script:taskName -TaskPath $script:taskPath -ErrorAction SilentlyContinue
    if ($task) {
        if ($PSCmdlet.ShouldProcess("$script:taskPath$script:taskName", 'Unregister scheduled task')) {
            Unregister-ScheduledTask -TaskName $script:taskName -TaskPath $script:taskPath -Confirm:$false -ErrorAction SilentlyContinue
            Write-DefaultPrinterLog -Message "Unregistered logon task '$script:taskPath$script:taskName'."
        }
    }
    else {
        Write-DefaultPrinterLog -Message "Logon task '$script:taskPath$script:taskName' was not present."
    }

    Invoke-ForEachUserHive -Operation 'Restore default printer' `
        -ArgumentList @($WhatIfPreference) `
        -Action {
        param($hiveRoot, $whatIf)
        Restore-HiveDefaultPrinter -HiveRoot $hiveRoot -WhatIf:$whatIf
    }

    foreach ($fileName in 'Set-DefaultPrinter.User.ps1', 'DefaultPrinter.json') {
        $filePath = Join-Path -Path $script:payloadRoot -ChildPath $fileName
        if (Test-Path -LiteralPath $filePath -PathType Leaf) {
            if ($PSCmdlet.ShouldProcess($filePath, 'Remove staged payload file')) {
                Remove-Item -LiteralPath $filePath -Force -ErrorAction SilentlyContinue
                Write-DefaultPrinterLog -Message "Removed staged file '$filePath'."
            }
        }
    }

    try {
        Remove-Hklm64Key -Path $script:sentinelPath -WhatIf:$WhatIfPreference
        Write-DefaultPrinterLog -Message "Removed detection sentinel HKLM:\$script:sentinelPath."
    }
    catch {
        Write-DefaultPrinterLog -Message "Detection sentinel was not present: $($_.Exception.Message)"
    }

    Write-DefaultPrinterLog -Message 'Default printer enforcement removed.'
}

try {
    Uninstall-DefaultPrinter -WhatIf:$WhatIfPreference
    exit 0
}
catch {
    $errorMessage = $_.Exception.Message
    try {
        Write-DefaultPrinterLog -Message $errorMessage -Level ERROR
    }
    catch {
        Write-Error -Message $errorMessage
    }
    exit 1
}
