<#
.SYNOPSIS
Makes a Pharos print queue the default printer for every user of the machine.

.DESCRIPTION
Runs as SYSTEM from an Intune Win32 app. Three things happen:

  1. The per-user payload (Set-DefaultPrinter.User.ps1 + DefaultPrinter.json) is
     staged under C:\ProgramData\UMD\Pharos.
  2. A scheduled task is registered that runs the payload at logon for every
     member of BUILTIN\Users, so future users and re-created profiles are
     covered without redeploying.
  3. The legacy default-printer values are written straight into the default
     user hive and every existing profile hive, so the change lands without
     waiting for a logon.

The default printer is a per-user (HKCU) setting, which is why a SYSTEM-context
install cannot simply set it once. Windows 10/11 also ships "Let Windows manage
my default printer" enabled, so LegacyDefaultPrinterMode is set to 1 or the
default silently moves to the last-used queue.

Detection state is written to HKLM:\SOFTWARE\UMD\Pharos\DefaultPrinter through
the 64-bit registry view, so a 32-bit install host does not strand it in
Wow6432Node.

.PARAMETER ConfigPath
Path to DefaultPrinter.json. Relative paths resolve from the script directory,
or the current directory when the script is pasted into Intune.

.EXAMPLE
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-DefaultPrinter.ps1

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-08-12
Version: 1.0.0
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [string]$ConfigPath = 'DefaultPrinter.json'
)

$ErrorActionPreference = 'Stop'

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path -Path $scriptDir -ChildPath $ConfigPath
}

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

function Set-Hklm64Value {
    <#
    .SYNOPSIS
    Writes an HKLM value through the 64-bit registry view.

    .DESCRIPTION
    HKLM\SOFTWARE is WOW64-redirected, so a 32-bit PowerShell host would write
    the detection sentinel into Wow6432Node where a 64-bit detection script
    cannot see it. Opening the Registry64 view sidesteps the redirection
    regardless of which host Intune uses.

    .PARAMETER Path
    Subkey path below HKLM.

    .PARAMETER Name
    Value name.

    .PARAMETER Value
    Value data.

    .PARAMETER Type
    Registry value kind.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter()]
        [ValidateSet('String', 'DWord', 'MultiString')]
        [string]$Type = 'String'
    )

    if (-not $PSCmdlet.ShouldProcess("HKLM:\$Path\$Name", 'Set registry value')) {
        return
    }

    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key = $baseKey.CreateSubKey($Path)
        try {
            $key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]$Type)
        }
        finally {
            $key.Dispose()
        }
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
    Returns the user hives that should receive the default printer setting.

    .DESCRIPTION
    Emits the default user profile plus every real (non-special) local profile,
    flagged with whether its hive is already loaded under HKEY_USERS.

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
    instead of aborting the whole install.

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

function Get-PrinterPortName {
    <#
    .SYNOPSIS
    Returns the port backing a local print queue.

    .PARAMETER Name
    Print queue name.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $printer = Get-CimInstance -ClassName Win32_Printer -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if ($printer) {
        return [string]$printer.PortName
    }

    # HKLM\SYSTEM is not WOW64-redirected, so the raw spooler key is a safe
    # fallback when WMI is unavailable during a servicing window.
    $spoolerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers\$Name"
    if (Test-Path -LiteralPath $spoolerKey) {
        return [string](Get-ItemProperty -LiteralPath $spoolerKey -Name 'Port' -ErrorAction SilentlyContinue).Port
    }

    return $null
}

function Set-HiveDefaultPrinter {
    <#
    .SYNOPSIS
    Writes the legacy default printer values into one user hive.

    .DESCRIPTION
    Backs up the previous Device value and LegacyDefaultPrinterMode under
    Software\UMD\Pharos\DefaultPrinter in the same hive so Uninstall can put
    them back. The backup is written once and never overwritten, so repeated
    installs cannot lose the user's original default.

    .PARAMETER HiveRoot
    Provider path to the hive root, e.g. Registry::HKEY_USERS\S-1-5-21-...

    .PARAMETER PrinterName
    Print queue name.

    .PARAMETER PortName
    Port backing the print queue.

    .PARAMETER OverrideExistingDefault
    Replace a default the user has already chosen. When false, a hive that
    already names some other printer is left alone.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$HiveRoot,

        [Parameter(Mandatory)]
        [string]$PrinterName,

        [Parameter(Mandatory)]
        [string]$PortName,

        [Parameter()]
        [bool]$OverrideExistingDefault = $true
    )

    $windowsKey = "$HiveRoot\Software\Microsoft\Windows NT\CurrentVersion\Windows"
    $devicesKey = "$HiveRoot\Software\Microsoft\Windows NT\CurrentVersion\Devices"
    $portsKey = "$HiveRoot\Software\Microsoft\Windows NT\CurrentVersion\PrinterPorts"
    $backupKey = "$HiveRoot\$script:backupSubKey"

    $deviceValue = '{0},winspool,{1}' -f $PrinterName, $PortName
    $existingDevice = [string](Get-ItemProperty -LiteralPath $windowsKey -Name 'Device' -ErrorAction SilentlyContinue).Device

    if (-not $OverrideExistingDefault -and $existingDevice -and $existingDevice -notlike "$PrinterName,*") {
        return 'Skipped (existing default: {0})' -f $existingDevice.Split(',')[0]
    }

    if (-not $PSCmdlet.ShouldProcess($HiveRoot, "Set default printer to $PrinterName")) {
        return 'WhatIf'
    }

    foreach ($keyPath in @($windowsKey, $devicesKey, $portsKey, $backupKey)) {
        if (-not (Test-Path -LiteralPath $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }
    }

    $backup = Get-ItemProperty -LiteralPath $backupKey -ErrorAction SilentlyContinue
    if (-not ($backup -and $backup.PSObject.Properties['PreviousDevice'])) {
        $previousMode = (Get-ItemProperty -LiteralPath $windowsKey -Name 'LegacyDefaultPrinterMode' -ErrorAction SilentlyContinue).LegacyDefaultPrinterMode
        Set-ItemProperty -LiteralPath $backupKey -Name 'PreviousDevice' -Value ([string]$existingDevice) -Force
        Set-ItemProperty -LiteralPath $backupKey -Name 'PreviousLegacyDefaultPrinterMode' -Value ([string]$previousMode) -Force
    }

    Set-ItemProperty -LiteralPath $windowsKey -Name 'Device' -Value $deviceValue -Force
    New-ItemProperty -LiteralPath $windowsKey -Name 'LegacyDefaultPrinterMode' -Value 1 -PropertyType DWord -Force | Out-Null
    Set-ItemProperty -LiteralPath $devicesKey -Name $PrinterName -Value ('winspool,{0}' -f $PortName) -Force
    Set-ItemProperty -LiteralPath $portsKey -Name $PrinterName -Value ('winspool,{0},15,45' -f $PortName) -Force

    Set-ItemProperty -LiteralPath $backupKey -Name 'AppliedPrinter' -Value $PrinterName -Force
    Set-ItemProperty -LiteralPath $backupKey -Name 'AppliedOnUtc' -Value ((Get-Date).ToUniversalTime().ToString('o')) -Force

    return 'Applied'
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
    Extra arguments passed to Action after the hive root. Passed explicitly
    rather than relied on through PowerShell's dynamic scope chain.

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

function Install-DefaultPrinterPayload {
    <#
    .SYNOPSIS
    Stages the per-user script and configuration under ProgramData.

    .PARAMETER Configuration
    Validated package configuration.

    .PARAMETER SourceDirectory
    Directory holding the bundled payload files.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration,

        [Parameter(Mandatory)]
        [string]$SourceDirectory
    )

    $sourceScript = Join-Path -Path $SourceDirectory -ChildPath 'Set-DefaultPrinter.User.ps1'
    if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) {
        throw "Bundled payload was not found: $sourceScript"
    }

    if (-not $PSCmdlet.ShouldProcess($script:payloadRoot, 'Stage per-user default printer payload')) {
        return (Join-Path -Path $script:payloadRoot -ChildPath 'Set-DefaultPrinter.User.ps1')
    }

    if (-not (Test-Path -LiteralPath $script:payloadRoot)) {
        New-Item -Path $script:payloadRoot -ItemType Directory -Force | Out-Null
    }

    Copy-Item -LiteralPath $sourceScript -Destination $script:payloadRoot -Force
    $Configuration | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path -Path $script:payloadRoot -ChildPath 'DefaultPrinter.json') -Encoding UTF8 -Force

    return (Join-Path -Path $script:payloadRoot -ChildPath 'Set-DefaultPrinter.User.ps1')
}

function Register-DefaultPrinterTask {
    <#
    .SYNOPSIS
    Registers the logon task that enforces the default printer per user.

    .DESCRIPTION
    The principal is BUILTIN\Users by SID so the task fires for whichever user
    signs in, including profiles created after this app was installed.

    .PARAMETER PayloadPath
    Full path to the staged per-user script.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$PayloadPath
    )

    if (-not $PSCmdlet.ShouldProcess("$script:taskPath$script:taskName", 'Register scheduled task')) {
        return
    }

    $argument = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $PayloadPath
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $argument
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    # S-1-5-32-545 is BUILTIN\Users; the SID avoids breaking on localized builds.
    $principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

    Register-ScheduledTask -TaskName $script:taskName `
        -TaskPath $script:taskPath `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description 'Sets the UMD Libraries default printer for the signed-in user.' `
        -Force | Out-Null
}

function Install-DefaultPrinter {
    <#
    .SYNOPSIS
    Installs and verifies the default printer configuration.

    .PARAMETER ConfigurationPath
    Path to DefaultPrinter.json.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigurationPath
    )

    if (-not (Test-Path -LiteralPath $ConfigurationPath -PathType Leaf)) {
        throw "Package configuration was not found: $ConfigurationPath"
    }

    $configuration = Get-Content -LiteralPath $ConfigurationPath -Raw | ConvertFrom-Json
    foreach ($propertyName in 'PackageId', 'DisplayName', 'Version', 'PrinterName') {
        if (-not $configuration.PSObject.Properties[$propertyName]) {
            throw "Package configuration is missing '$propertyName'."
        }
    }

    $printerName = [string]$configuration.PrinterName
    $override = $true
    if ($configuration.PSObject.Properties['OverrideExistingDefault']) {
        $override = [bool]$configuration.OverrideExistingDefault
    }

    Write-DefaultPrinterLog -Message "Configuring '$($configuration.DisplayName)' version $($configuration.Version)."

    $portName = Get-PrinterPortName -Name $printerName
    if (-not $portName) {
        throw "Print queue '$printerName' is not installed on this machine. Deploy the Pharos package first and set it as a dependency of this app."
    }

    Write-DefaultPrinterLog -Message "Found print queue '$printerName' on port '$portName'."

    $payloadPath = Install-DefaultPrinterPayload -Configuration $configuration -SourceDirectory $scriptDir -WhatIf:$WhatIfPreference
    Write-DefaultPrinterLog -Message "Per-user payload staged at '$payloadPath'."

    Register-DefaultPrinterTask -PayloadPath $payloadPath -WhatIf:$WhatIfPreference
    Write-DefaultPrinterLog -Message "Logon task '$script:taskPath$script:taskName' registered for BUILTIN\Users."

    Invoke-ForEachUserHive -Operation 'Default printer' `
        -ArgumentList @($printerName, $portName, $override, $WhatIfPreference) `
        -Action {
        param($hiveRoot, $queueName, $queuePort, $replaceExisting, $whatIf)
        Set-HiveDefaultPrinter -HiveRoot $hiveRoot `
            -PrinterName $queueName `
            -PortName $queuePort `
            -OverrideExistingDefault $replaceExisting `
            -WhatIf:$whatIf
    }

    Set-Hklm64Value -Path $script:sentinelPath -Name 'PrinterName' -Value $printerName -WhatIf:$WhatIfPreference
    Set-Hklm64Value -Path $script:sentinelPath -Name 'DisplayName' -Value ([string]$configuration.DisplayName) -WhatIf:$WhatIfPreference
    Set-Hklm64Value -Path $script:sentinelPath -Name 'Version' -Value ([string]$configuration.Version) -WhatIf:$WhatIfPreference
    Set-Hklm64Value -Path $script:sentinelPath -Name 'PayloadPath' -Value $payloadPath -WhatIf:$WhatIfPreference
    Set-Hklm64Value -Path $script:sentinelPath -Name 'TaskName' -Value "$script:taskPath$script:taskName" -WhatIf:$WhatIfPreference
    Set-Hklm64Value -Path $script:sentinelPath -Name 'ConfiguredOnUtc' -Value ((Get-Date).ToUniversalTime().ToString('o')) -WhatIf:$WhatIfPreference

    Write-DefaultPrinterLog -Message "Detection sentinel written to HKLM:\$script:sentinelPath."
    Write-DefaultPrinterLog -Message 'Default printer configuration completed.'
}

try {
    Install-DefaultPrinter -ConfigurationPath $ConfigPath -WhatIf:$WhatIfPreference
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
