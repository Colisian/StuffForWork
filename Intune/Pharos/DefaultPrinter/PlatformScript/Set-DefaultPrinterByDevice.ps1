<#
.SYNOPSIS
Sets the signed-in user's default printer based on the device name.

.DESCRIPTION
Intune platform script, deployed to run in the logged-on user's context at every
sign-in. Maps the computer name to a library location using the same hostname
prefixes as the legacy PSADT deployment (Deploy-Application.ps1), then makes that
location's queue the default printer for the current user.

Two things make this reliable where a naive default-printer script is not:

  - Windows 10/11 ship "Let Windows manage my default printer" enabled, which
    silently re-points the default at the most recently used queue. The script
    clears it via LegacyDefaultPrinterMode.
  - On a freshly imaged PC this can run before the Pharos package has created
    the queues, so it waits for the queue to appear rather than failing outright.

The mapping is inline rather than in a companion JSON file: an Intune platform
script is a single uploaded .ps1 with no bundled payload.

Rule matching is most-specific-wins, not first-match-wins. 'LIBRWKMCKP2WF*' and
'LIBRWKMCK*' both match a wide-format station, and the longer literal prefix
takes it. Reordering the table cannot silently break that.

.PARAMETER PrinterWaitSeconds
How long to wait for the mapped queue to appear before reporting failure. Only
applies when the queue is not already present.

.EXAMPLE
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Set-DefaultPrinterByDevice.ps1

.EXAMPLE
.\Set-DefaultPrinterByDevice.ps1 -WhatIf

Reports the rule that would match this device without changing anything.

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-08-12
Version: 1.0.0

Intune platform script settings:
  Run this script using the logged on credentials : Yes
  Enforce script signature check                  : No
  Run script in 64 bit PowerShell Host            : Yes
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter()]
    [ValidateRange(0, 600)]
    [int]$PrinterWaitSeconds = 90
)

$ErrorActionPreference = 'Stop'

# ---- Device name to default printer map ----------------------------------
# Prefixes come from the legacy PSADT deployment, Deploy-Application.ps1:210-215.
#
# PrinterName is a CANDIDATE LIST, tried in order; the first queue that actually
# exists on the device wins.
#
# The real queue names carry NO 'LIB-' prefix. That prefix appears only on the
# vendor installer filenames and inside their manifests -- Pharos strips it when
# it creates the local spool queue. Confirmed by running
# Get-PharosPrinterInventory.ps1 on real hardware (see PharosDiscovery\):
#
#   LIBRWKMCKP2WF1  -> Mck2FWideFormat, McKeldinBW, McKeldinColor
#   LIBRWKSTEMP1F1  -> EPSLBW, EPSLColor
#   Art PC          -> ArtBW, ArtColor
#   LIBRWKPALP1F2   -> PALBW, PALColor
#   LIBRWKARCHP1F1  -> ArchBW, ArchColor
#
# Note McKeldin differs beyond the prefix too: the queue is 'McKeldinBW', not
# the 'MckBW' that PerLibrary/Definitions/McKeldin/Package.json claims.
#
# STEM-named devices legitimately carry the EPSL queues - the library was
# renamed but the print queues were not. That mismatch is expected, not a typo.
#
# Maryland Room is the one site with no discovery output yet, so it keeps a
# candidate list as a safety net. Run Get-PharosPrinterInventory.ps1 on a
# Maryland Room PC and reduce that rule to the single real name.
$script:deviceRule = @(
    # --- verified against real hardware ---
    [pscustomobject]@{ Pattern = 'LIBRWKMCKP2WF*'; PrinterName = @('Mck2FWideFormat'); Location = 'McKeldin 2nd Floor Wide Format' }
    [pscustomobject]@{ Pattern = 'LIBRWKMCK*'; PrinterName = @('McKeldinBW'); Location = 'McKeldin Library' }
    [pscustomobject]@{ Pattern = 'LIBRWKSTEM*'; PrinterName = @('EPSLBW'); Location = 'STEM Library (EPSL queues)' }
    [pscustomobject]@{ Pattern = 'LIBRWKART*'; PrinterName = @('ArtBW'); Location = 'Art Library' }
    [pscustomobject]@{ Pattern = 'LIBRWKPAL*'; PrinterName = @('PALBW'); Location = 'Performing Arts Library' }
    [pscustomobject]@{ Pattern = 'LIBRWKARCH*'; PrinterName = @('ArchBW'); Location = 'Architecture Library' }

    # --- UNVERIFIED: candidates until discovery is run at Maryland Room ---
    [pscustomobject]@{ Pattern = 'LIBRWKMDRP*'; PrinterName = @('MarylandRoomBW', 'LIB-MarylandRoomBW'); Location = 'Maryland Room' }
)

# ProgramData keeps every location's logs together, and a per-user filename means
# each user owns their own file so a standard account can append to it. Falls back
# to the profile if ProgramData is not writable.
$script:logPath = Join-Path -Path $env:ProgramData -ChildPath "UMD\Pharos\Logs\DefaultPrinter-$env:USERNAME.log"
$script:logFallbackPath = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'UMD\Logs\DefaultPrinter-User.log'

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

    $entry = '[{0}][{1}][{2}] {3}' -f (Get-Date).ToString('s'), $Level, $env:COMPUTERNAME, $Message
    Write-Host $entry

    foreach ($candidate in @($script:logPath, $script:logFallbackPath)) {
        try {
            $logDirectory = Split-Path -Path $candidate -Parent
            if (-not (Test-Path -LiteralPath $logDirectory)) {
                New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
            }

            # This runs at every sign-in, so cap growth rather than letting the
            # file accumulate indefinitely on a shared lab PC.
            if ((Test-Path -LiteralPath $candidate) -and (Get-Item -LiteralPath $candidate).Length -gt 256KB) {
                $tail = Get-Content -LiteralPath $candidate -Tail 500
                Set-Content -LiteralPath $candidate -Value $tail -Encoding UTF8
            }

            Add-Content -LiteralPath $candidate -Value $entry -Encoding UTF8
            return
        }
        catch {
            # Try the next candidate; logging must never fail the script.
        }
    }
}

function Get-DevicePrinterRule {
    <#
    .SYNOPSIS
    Returns the default printer rule matching a device name.

    .DESCRIPTION
    Selects the most specific match rather than the first, so a longer prefix
    such as LIBRWKMCKP2WF always beats the broader LIBRWKMCK regardless of the
    order rules appear in the table.

    .PARAMETER DeviceName
    Computer name to match.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceName
    )

    $match = @($script:deviceRule | Where-Object { $DeviceName -like $_.Pattern })
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
    Excludes RDP-redirected queues. Those belong to the remote client, carry a
    "(redirected N)" suffix, and vanish with the session, so making one the
    default would be meaningless.

    Filtering happens client-side rather than through a WQL -Filter because the
    friendly queue names contain spaces and ampersands, which are awkward to
    escape safely in a WQL string literal.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    return @(Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '\(redirected \d+\)$' })
}

function Resolve-PrinterQueue {
    <#
    .SYNOPSIS
    Waits for any of the candidate queue names to appear, and returns the first
    one present.

    .PARAMETER CandidateName
    Queue names to try, in order of preference.

    .PARAMETER TimeoutSeconds
    Maximum time to wait.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$CandidateName,

        [Parameter()]
        [ValidateRange(0, 600)]
        [int]$TimeoutSeconds = 90
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

        Start-Sleep -Seconds 5
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

    if (-not $PSCmdlet.ShouldProcess($PrinterName, 'Write legacy default printer registry values')) {
        return
    }

    $windowsKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'
    $devicesKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Devices'
    $portsKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\PrinterPorts'

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

function Test-DefaultPrinterState {
    <#
    .SYNOPSIS
    Tests whether the named queue is already the enforced default.

    .PARAMETER CandidateName
    Acceptable queue names for this device.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$CandidateName
    )

    $default = Get-LocalPrinter | Where-Object { $_.Default } | Select-Object -First 1
    if (-not ($default -and $default.Name -in $CandidateName)) {
        return $false
    }

    $legacyMode = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' `
            -Name 'LegacyDefaultPrinterMode' -ErrorAction SilentlyContinue).LegacyDefaultPrinterMode

    # Without LegacyDefaultPrinterMode the default is correct only until the user
    # prints somewhere else, so that is not a compliant state.
    return ($legacyMode -eq 1)
}

function Set-DeviceDefaultPrinter {
    <#
    .SYNOPSIS
    Applies the device-mapped default printer for the current user.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-12
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param()

    $rule = Get-DevicePrinterRule -DeviceName $env:COMPUTERNAME
    if (-not $rule) {
        # Not an error: the assignment simply includes a device outside the map.
        Write-DefaultPrinterLog -Message "No default printer rule matches this device name; leaving the default unchanged."
        return 0
    }

    $candidateList = @($rule.PrinterName) -join "', '"
    Write-DefaultPrinterLog -Message "Matched '$($rule.Pattern)' -> $($rule.Location); candidate queues '$candidateList'."

    if (Test-DefaultPrinterState -CandidateName $rule.PrinterName) {
        Write-DefaultPrinterLog -Message 'Default printer is already correct and enforced; nothing to do.'
        return 0
    }

    $printer = Resolve-PrinterQueue -CandidateName $rule.PrinterName -TimeoutSeconds $PrinterWaitSeconds
    if (-not $printer) {
        Write-DefaultPrinterLog -Message "None of the candidate queues ('$candidateList') appeared within ${PrinterWaitSeconds}s. Is the Pharos package for $($rule.Location) assigned to this device, and do the names in the rule table match the real queue names? Run Get-PharosPrinterInventory.ps1 on this PC to list them." -Level ERROR
        return 1
    }

    if ($PSCmdlet.ShouldProcess($printer.Name, 'Set as default printer')) {
        $currentDefault = Get-LocalPrinter | Where-Object { $_.Default } | Select-Object -First 1

        $result = Invoke-CimMethod -InputObject $printer -MethodName 'SetDefaultPrinter' -ErrorAction SilentlyContinue
        if ($result -and $result.ReturnValue -eq 0) {
            Write-DefaultPrinterLog -Message "Default changed from '$(if ($currentDefault) { $currentDefault.Name } else { 'none' })' to '$($printer.Name)'."
        }
        else {
            $returnValue = if ($result) { $result.ReturnValue } else { 'no result' }
            Write-DefaultPrinterLog -Message "Win32_Printer.SetDefaultPrinter returned $returnValue; relying on the registry values." -Level WARN
        }
    }

    # Always written: SetDefaultPrinter does not clear LegacyDefaultPrinterMode,
    # so without this Windows can take the default back later in the session.
    Set-LegacyDefaultPrinterValue -PrinterName $printer.Name -PortName $printer.PortName -WhatIf:$WhatIfPreference

    Write-DefaultPrinterLog -Message "Default printer enforced: '$($printer.Name)' on port '$($printer.PortName)'."
    return 0
}

try {
    $exitCode = Set-DeviceDefaultPrinter -WhatIf:$WhatIfPreference
    exit $exitCode
}
catch {
    try {
        Write-DefaultPrinterLog -Message $_.Exception.Message -Level ERROR
    }
    catch {
        Write-Error -Message $_.Exception.Message
    }
    exit 1
}
