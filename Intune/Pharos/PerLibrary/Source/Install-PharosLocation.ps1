<#
.SYNOPSIS
Installs the Pharos Popup printer package defined in Package.json.

.DESCRIPTION
Validates each bundled vendor installer by SHA-256, runs it silently, verifies
the expected printer queues and Pharos Popup client, and writes an Intune
detection sentinel under HKLM.

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

$script:logPath = Join-Path -Path $env:ProgramData -ChildPath 'UMD\Pharos\Logs\Pharos-Install.log'

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
    foreach ($propertyName in 'PackageId', 'DisplayName', 'Version', 'Installers', 'ExpectedPrinters') {
        if (-not $configuration.PSObject.Properties[$propertyName]) {
            throw "Package configuration is missing '$propertyName'."
        }
    }

    if ($configuration.PackageId -notmatch '^[A-Za-z0-9-]+$') {
        throw "PackageId '$($configuration.PackageId)' contains unsupported characters."
    }

    if (@($configuration.Installers).Count -eq 0 -or @($configuration.ExpectedPrinters).Count -eq 0) {
        throw 'Package configuration must define at least one installer and one expected printer.'
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

function Get-PharosFileHash {
    <#
    .SYNOPSIS
    Calculates a SHA-256 hash without changing WhatIf behavior.

    .PARAMETER Path
    File to hash.

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

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            return ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '')
        }
        finally {
            $sha256.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Test-PharosPrinterState {
    <#
    .SYNOPSIS
    Tests whether all configured Pharos printer queues are installed.

    .PARAMETER ExpectedPrinter
    Printer queue names that must exist.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-07-27
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ExpectedPrinter
    )

    $installedPrinter = Get-InstalledPrinterName
    return @($ExpectedPrinter | Where-Object { $_ -notin $installedPrinter }).Count -eq 0
}

function Wait-PharosPrinterState {
    <#
    .SYNOPSIS
    Waits for all configured Pharos printer queues to appear.

    .PARAMETER ExpectedPrinter
    Printer queue names that must exist.

    .PARAMETER TimeoutSeconds
    Maximum wait time.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-07-27
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ExpectedPrinter,

        [Parameter()]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 45
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-PharosPrinterState -ExpectedPrinter $ExpectedPrinter) {
            return $true
        }

        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Invoke-PharosVendorInstaller {
    <#
    .SYNOPSIS
    Validates and runs one bundled Pharos vendor installer.

    .PARAMETER Installer
    Installer definition from Package.json.

    .PARAMETER SourceDirectory
    Directory containing the bundled installer.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-07-27
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Installer,

        [Parameter(Mandatory)]
        [string]$SourceDirectory
    )

    $installerPath = Join-Path -Path $SourceDirectory -ChildPath $Installer.FileName
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        throw "Bundled installer was not found: $installerPath"
    }

    $actualHash = Get-PharosFileHash -Path $installerPath
    if ($actualHash -ne $Installer.Sha256) {
        throw "SHA-256 mismatch for '$($Installer.FileName)'. Expected $($Installer.Sha256); found $actualHash."
    }

    if (-not $PSCmdlet.ShouldProcess($installerPath, 'Run silent Pharos vendor installer')) {
        return 0
    }

    Write-PharosLog -Message "Running '$($Installer.FileName)' with arguments '$($Installer.Arguments)'."
    $process = Start-Process -FilePath $installerPath `
        -ArgumentList $Installer.Arguments `
        -WindowStyle Hidden `
        -Wait `
        -PassThru

    Write-PharosLog -Message "Installer '$($Installer.FileName)' returned exit code $($process.ExitCode)."
    if ($process.ExitCode -notin 0, 3010) {
        throw "Installer '$($Installer.FileName)' returned non-success exit code $($process.ExitCode)."
    }

    return $process.ExitCode
}

function Set-PharosDetectionState {
    <#
    .SYNOPSIS
    Writes the registry state used by the Intune detection rule.

    .PARAMETER Configuration
    Validated package configuration.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-07-27
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration
    )

    $registryPath = "HKLM:\SOFTWARE\UMD\Pharos\Packages\$($Configuration.PackageId)"
    if (-not $PSCmdlet.ShouldProcess($registryPath, 'Write Intune detection state')) {
        return
    }

    if (-not (Test-Path -LiteralPath $registryPath)) {
        New-Item -Path $registryPath -Force | Out-Null
    }

    $properties = @{
        DisplayName      = [string]$Configuration.DisplayName
        Version          = [string]$Configuration.Version
        InstalledOnUtc   = (Get-Date).ToUniversalTime().ToString('o')
        ExpectedPrinters = [string[]]@($Configuration.ExpectedPrinters)
    }

    foreach ($property in $properties.GetEnumerator()) {
        Set-ItemProperty -LiteralPath $registryPath -Name $property.Key -Value $property.Value -Force
    }
}

function Install-PharosLocation {
    <#
    .SYNOPSIS
    Installs and verifies one configured Pharos location package.

    .PARAMETER ConfigurationPath
    Path to the package configuration.

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
    $script:logPath = Join-Path -Path $env:ProgramData -ChildPath "UMD\Pharos\Logs\Pharos-$($configuration.PackageId)-Install.log"
    Write-PharosLog -Message "Starting installation of '$($configuration.DisplayName)' version $($configuration.Version)."

    $popupPath = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Pharos\Bin\Popup.exe'
    $rebootRequired = $false

    $printerStateValid = if ($WhatIfPreference) {
        $false
    }
    else {
        Test-PharosPrinterState -ExpectedPrinter @($configuration.ExpectedPrinters)
    }
    $popupStateValid = Test-Path -LiteralPath $popupPath -PathType Leaf
    if (-not ($printerStateValid -and $popupStateValid)) {
        if ($PSCmdlet.ShouldProcess('Popup.exe', 'Stop running processes before installation')) {
            Get-Process -Name Popup -ErrorAction SilentlyContinue | ForEach-Object {
                Write-PharosLog -Message "Stopping Popup.exe process ID $($_.Id)." -Level WARN
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        }

        foreach ($installer in @($configuration.Installers)) {
            $exitCode = Invoke-PharosVendorInstaller `
                -Installer $installer `
                -SourceDirectory $scriptDir `
                -WhatIf:$WhatIfPreference
            if ($exitCode -eq 3010) {
                $rebootRequired = $true
            }
        }
    }
    else {
        Write-PharosLog -Message 'All expected printer queues already exist; vendor installers were skipped.'
    }

    if (-not $WhatIfPreference) {
        if (-not (Test-Path -LiteralPath $popupPath -PathType Leaf)) {
            throw "Pharos Popup client verification failed. Missing file: $popupPath"
        }

        if (-not (Wait-PharosPrinterState -ExpectedPrinter @($configuration.ExpectedPrinters))) {
            $installedPrinter = Get-InstalledPrinterName
            $missingPrinter = @($configuration.ExpectedPrinters | Where-Object { $_ -notin $installedPrinter })
            throw "Printer verification failed. Missing: $($missingPrinter -join ', ')"
        }
    }

    Set-PharosDetectionState -Configuration $configuration -WhatIf:$WhatIfPreference
    Write-PharosLog -Message "Installation and verification completed for '$($configuration.DisplayName)'."

    if ($rebootRequired) {
        return 3010
    }

    return 0
}

try {
    $result = Install-PharosLocation -ConfigurationPath $ConfigPath -WhatIf:$WhatIfPreference
    exit $result
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
