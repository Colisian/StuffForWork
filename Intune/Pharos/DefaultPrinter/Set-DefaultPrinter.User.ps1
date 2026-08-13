<#
.SYNOPSIS
Sets the signed-in user's default printer from the device-name rules in
DefaultPrinter.json.

.DESCRIPTION
Runs in the interactive user's context, launched at logon by the scheduled task
that Install-DefaultPrinter.ps1 registers. Maps the computer name to a library
location, waits briefly for that queue to appear (the Pharos package may still
be installing on a freshly imaged machine), sets the default through
Win32_Printer, and writes the legacy HKCU printer values as a backstop. Also
clears "Let Windows manage my default printer", which otherwise reverts the
default to the last-used queue.

This script never throws to the caller: a failure here must not stall a logon.

.PARAMETER ConfigPath
Path to DefaultPrinter.json. Relative paths resolve from the script directory,
or the current directory when the script is pasted into a host without
$PSScriptRoot.

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-08-12
Version: 1.0.0
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter()]
    [string]$ConfigPath = 'DefaultPrinter.json'
)

$ErrorActionPreference = 'Stop'

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path -Path $scriptDir -ChildPath $ConfigPath
}

# Per-user log: ProgramData ACLs let Users create files but not append to files
# owned by SYSTEM, so the user-context log lives in the user's own profile.
$script:logPath = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'UMD\Logs\DefaultPrinter-User.log'

function Write-DefaultPrinterLog {
    <#
    .SYNOPSIS
    Writes a timestamped entry to the per-user default printer log.

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

    try {
        $logDirectory = Split-Path -Path $script:logPath -Parent
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }
        Add-Content -LiteralPath $script:logPath -Value $entry -Encoding UTF8
    }
    catch {
        # Logging must never be the reason this script fails.
    }
}

function Get-DevicePrinterRule {
    <#
    .SYNOPSIS
    Returns the rule matching a device name, or $null when out of scope.

    .DESCRIPTION
    Most-specific match wins, so 'LIBRWKMCKP2WF*' beats the broader
    'LIBRWKMCK*' regardless of the order rules appear in DefaultPrinter.json.

    .PARAMETER Rule
    Rule objects from DefaultPrinter.json.

    .PARAMETER DeviceName
    Computer name to match.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rule,

        [Parameter(Mandatory)]
        [string]$DeviceName
    )

    $match = @($Rule | Where-Object { $DeviceName -like $_.Pattern })
    if ($match.Count -eq 0) {
        return $null
    }

    return ($match | Sort-Object -Property @{ Expression = { $_.Pattern.TrimEnd('*').Length } } -Descending |
        Select-Object -First 1)
}

function Get-LocalPrinter {
    <#
    .SYNOPSIS
    Returns the print queues genuinely installed on this machine.

    .DESCRIPTION
    Excludes RDP-redirected queues, which belong to the remote client and vanish
    with the session.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 2.0.0
    #>
    [CmdletBinding()]
    param()

    return @(Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '\(redirected \d+\)$' })
}

function Resolve-PrinterQueue {
    <#
    .SYNOPSIS
    Waits for any of the candidate queue names to appear and returns the first
    one present.

    .PARAMETER CandidateName
    Queue names to try, in order of preference.

    .PARAMETER TimeoutSeconds
    Maximum time to wait.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$CandidateName,

        [Parameter()]
        [ValidateRange(0, 600)]
        [int]$TimeoutSeconds = 60
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $installed = Get-LocalPrinter
        foreach ($candidate in $CandidateName) {
            $printer = $installed | Where-Object { $_.Name -eq $candidate } | Select-Object -First 1
            if ($printer) {
                return $printer
            }
        }

        if ((Get-Date) -ge $deadline) {
            break
        }

        Start-Sleep -Seconds 3
    } while ($true)

    return $null
}

function Set-LegacyDefaultPrinterValue {
    <#
    .SYNOPSIS
    Writes the legacy HKCU registry values that identify the default printer.

    .DESCRIPTION
    Mirrors what the spooler writes when a user picks a default printer, and
    sets LegacyDefaultPrinterMode so Windows stops re-pointing the default at
    the most recently used queue.

    .PARAMETER PrinterName
    Print queue name.

    .PARAMETER PortName
    Port backing the print queue.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,

        [Parameter(Mandatory)]
        [string]$PortName
    )

    $windowsKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'
    $devicesKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Devices'
    $portsKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\PrinterPorts'

    if (-not $PSCmdlet.ShouldProcess($PrinterName, 'Write legacy default printer registry values')) {
        return
    }

    foreach ($keyPath in @($windowsKey, $devicesKey, $portsKey)) {
        if (-not (Test-Path -LiteralPath $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }
    }

    Set-ItemProperty -LiteralPath $windowsKey -Name 'Device' -Value ('{0},winspool,{1}' -f $PrinterName, $PortName) -Force
    New-ItemProperty -LiteralPath $windowsKey -Name 'LegacyDefaultPrinterMode' -Value 1 -PropertyType DWord -Force | Out-Null
    Set-ItemProperty -LiteralPath $devicesKey -Name $PrinterName -Value ('winspool,{0}' -f $PortName) -Force
    Set-ItemProperty -LiteralPath $portsKey -Name $PrinterName -Value ('winspool,{0},15,45' -f $PortName) -Force
}

function Set-UserDefaultPrinter {
    <#
    .SYNOPSIS
    Applies the configured default printer to the current user.

    .PARAMETER ConfigurationPath
    Path to DefaultPrinter.json.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigurationPath
    )

    if (-not (Test-Path -LiteralPath $ConfigurationPath -PathType Leaf)) {
        throw "Package configuration was not found: $ConfigurationPath"
    }

    $configuration = Get-Content -LiteralPath $ConfigurationPath -Raw | ConvertFrom-Json
    if (-not $configuration.PSObject.Properties['Rules']) {
        throw 'Package configuration is missing Rules.'
    }

    $override = $true
    if ($configuration.PSObject.Properties['OverrideExistingDefault']) {
        $override = [bool]$configuration.OverrideExistingDefault
    }

    $waitSeconds = 60
    if ($configuration.PSObject.Properties['PrinterWaitSeconds']) {
        $waitSeconds = [int]$configuration.PrinterWaitSeconds
    }

    $rule = Get-DevicePrinterRule -Rule @($configuration.Rules) -DeviceName $env:COMPUTERNAME
    if (-not $rule) {
        Write-DefaultPrinterLog -Message "No rule matches device '$env:COMPUTERNAME'; leaving the default unchanged."
        return
    }

    $candidateList = @($rule.PrinterName) -join "', '"
    Write-DefaultPrinterLog -Message "User '$env:USERNAME': matched '$($rule.Pattern)' -> $($rule.Location); candidates '$candidateList'."

    $printer = Resolve-PrinterQueue -CandidateName @($rule.PrinterName) -TimeoutSeconds $waitSeconds
    if (-not $printer) {
        Write-DefaultPrinterLog -Message "None of the candidate queues ('$candidateList') are present after ${waitSeconds}s; nothing to do." -Level WARN
        return
    }

    if ($printer.Default) {
        Write-DefaultPrinterLog -Message "'$($printer.Name)' is already the default printer."
    }
    else {
        $currentDefault = Get-LocalPrinter | Where-Object { $_.Default } | Select-Object -First 1

        if ($currentDefault -and -not $override) {
            Write-DefaultPrinterLog -Message "Default is '$($currentDefault.Name)' and OverrideExistingDefault is false; leaving it unchanged."
            return
        }

        if ($PSCmdlet.ShouldProcess($printer.Name, 'Set as default printer')) {
            $result = Invoke-CimMethod -InputObject $printer -MethodName 'SetDefaultPrinter' -ErrorAction SilentlyContinue
            if ($result -and $result.ReturnValue -eq 0) {
                Write-DefaultPrinterLog -Message "Win32_Printer.SetDefaultPrinter succeeded (previous default: $(if ($currentDefault) { $currentDefault.Name } else { 'none' }))."
            }
            else {
                $returnValue = if ($result) { $result.ReturnValue } else { 'no result' }
                Write-DefaultPrinterLog -Message "Win32_Printer.SetDefaultPrinter returned $returnValue; falling back to registry values." -Level WARN
            }
        }
    }

    # Always write the legacy values: SetDefaultPrinter does not clear
    # LegacyDefaultPrinterMode, so without this Windows can take the default
    # back the next time the user prints somewhere else.
    Set-LegacyDefaultPrinterValue -PrinterName $printer.Name -PortName $printer.PortName -WhatIf:$WhatIfPreference
    Write-DefaultPrinterLog -Message "Default printer enforcement complete for '$($printer.Name)' (port '$($printer.PortName)')."
}

try {
    Set-UserDefaultPrinter -ConfigurationPath $ConfigPath -WhatIf:$WhatIfPreference
    exit 0
}
catch {
    Write-DefaultPrinterLog -Message $_.Exception.Message -Level ERROR
    # Exit 0 regardless: this runs during logon and must not surface an error to
    # the user or leave the task in a failed state that alarms the console.
    exit 0
}
