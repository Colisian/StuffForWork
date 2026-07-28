<#
.SYNOPSIS
Removes only the printer queues owned by a configured Pharos location package.

.DESCRIPTION
Removes the location-specific printer queues and Intune detection sentinel.
The shared Pharos Popup client, drivers, and other libraries' queues are left
in place intentionally.

.PARAMETER ConfigPath
Path to the bundled package configuration. Relative paths are resolved from
the script directory, or the current directory when pasted into Intune.

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-07-27
Version: 1.0.0
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [string]$ConfigPath = 'Package.json'
)

$ErrorActionPreference = 'Stop'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path -Path $scriptDir -ChildPath $ConfigPath
}

$script:logPath = Join-Path -Path $env:ProgramData -ChildPath 'UMD\Pharos\Logs\Pharos-Uninstall.log'

function Write-PharosLog {
    <#
    .SYNOPSIS
    Writes a timestamped entry to the Pharos deployment log.

    .PARAMETER Message
    Message to write.

    .PARAMETER Level
    Log severity.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-07-27
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

function Get-PharosConfiguration {
    <#
    .SYNOPSIS
    Reads and validates a Pharos package configuration.

    .PARAMETER Path
    Path to Package.json.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-07-27
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Package configuration was not found: $Path"
    }

    $configuration = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($propertyName in 'PackageId', 'DisplayName', 'Version', 'ExpectedPrinters') {
        if (-not $configuration.PSObject.Properties[$propertyName]) {
            throw "Package configuration is missing '$propertyName'."
        }
    }

    return $configuration
}

function Get-InstalledPrinterName {
    <#
    .SYNOPSIS
    Returns the names of locally installed printers.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-07-27
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    return @(Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop | Select-Object -ExpandProperty Name)
}

function Remove-PharosLocation {
    <#
    .SYNOPSIS
    Removes configured queues and the package detection sentinel.

    .PARAMETER ConfigurationPath
    Path to Package.json.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-07-27
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigurationPath
    )

    $configuration = Get-PharosConfiguration -Path $ConfigurationPath
    $script:logPath = Join-Path -Path $env:ProgramData -ChildPath "UMD\Pharos\Logs\Pharos-$($configuration.PackageId)-Uninstall.log"
    Write-PharosLog -Message "Starting selective uninstall of '$($configuration.DisplayName)'."

    $installedPrinter = if ($WhatIfPreference) {
        @($configuration.ExpectedPrinters)
    }
    else {
        Get-InstalledPrinterName
    }
    foreach ($printerName in @($configuration.ExpectedPrinters)) {
        if ($printerName -notin $installedPrinter) {
            Write-PharosLog -Message "Printer '$printerName' is already absent."
            continue
        }

        if ($PSCmdlet.ShouldProcess($printerName, 'Remove location-specific printer queue')) {
            Write-PharosLog -Message "Removing printer '$printerName'."
            Remove-Printer -Name $printerName -ErrorAction Stop
        }
    }

    if (-not $WhatIfPreference) {
        $remainingPrinter = Get-InstalledPrinterName
        $failedPrinter = @($configuration.ExpectedPrinters | Where-Object { $_ -in $remainingPrinter })
        if ($failedPrinter.Count -gt 0) {
            throw "Printer removal verification failed: $($failedPrinter -join ', ')"
        }
    }

    $registryPath = "HKLM:\SOFTWARE\UMD\Pharos\Packages\$($configuration.PackageId)"
    if ((Test-Path -LiteralPath $registryPath) -and $PSCmdlet.ShouldProcess($registryPath, 'Remove Intune detection state')) {
        Remove-Item -LiteralPath $registryPath -Recurse -Force
    }

    Write-PharosLog -Message 'Selective uninstall completed. The shared Pharos Popup client was retained.'
}

try {
    Remove-PharosLocation -ConfigurationPath $ConfigPath -WhatIf:$WhatIfPreference -Confirm:$false
    exit 0
}
catch {
    $errorMessage = $_.Exception.Message
    try {
        Write-PharosLog -Message $errorMessage -Level ERROR
    }
    catch {
        Write-Error -Message $errorMessage
    }
    exit 1
}
