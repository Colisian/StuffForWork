<#
.SYNOPSIS
Builds one Intune Win32 package per Pharos library/location.

.DESCRIPTION
Validates the source vendor EXEs against the pinned hashes in Definitions,
stages only the files needed by each location, and invokes IntuneWinAppUtil.

.PARAMETER InstallerSourcePath
Directory containing the seven Pharos vendor EXEs.

.PARAMETER IntuneWinAppUtilPath
Path to Microsoft IntuneWinAppUtil.exe.

.PARAMETER OutputPath
Directory that will receive the generated .intunewin files.

.PARAMETER PackageId
Optional list of package IDs to build. The default builds every definition.

.PARAMETER ValidateOnly
Validates definitions, source files, hashes, and tools without building.

.PARAMETER StageOnly
Creates one package-ready source folder per location without invoking
IntuneWinAppUtil.

.PARAMETER PackageSourceOutputPath
Directory that receives package-ready source folders when using StageOnly.

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-07-27
Version: 1.0.0
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [string]$InstallerSourcePath,

    [Parameter()]
    [string]$IntuneWinAppUtilPath,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [ValidateSet('Architecture', 'Art', 'EPSL', 'MarylandRoom', 'McKeldin', 'PAL')]
    [string[]]$PackageId,

    [Parameter()]
    [switch]$ValidateOnly,

    [Parameter()]
    [switch]$StageOnly,

    [Parameter()]
    [string]$PackageSourceOutputPath
)

$ErrorActionPreference = 'Stop'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$definitionRoot = Join-Path -Path $scriptDir -ChildPath 'Definitions'
$sourceScriptRoot = Join-Path -Path $scriptDir -ChildPath 'Source'
$script:packageStagingRoot = Join-Path -Path $scriptDir -ChildPath '.staging'
$documentsRoot = [Environment]::GetFolderPath('MyDocuments')
if ($env:OneDriveCommercial) {
    $oneDriveDocuments = Join-Path -Path $env:OneDriveCommercial -ChildPath 'Documents'
    if (Test-Path -LiteralPath $oneDriveDocuments -PathType Container) {
        $documentsRoot = $oneDriveDocuments
    }
}

if (-not $InstallerSourcePath) {
    $InstallerSourcePath = Join-Path -Path $documentsRoot -ChildPath 'Work\Intune\1-InstallationFiles\Pharos\PharosApp Deploy\Files'
}
if (-not $IntuneWinAppUtilPath) {
    $IntuneWinAppUtilPath = Join-Path -Path $documentsRoot -ChildPath 'Work\Intune\3.5-Microsoft-Win32-Content-Prep-Tool-master\IntuneWinAppUtil.exe'
}
if (-not $OutputPath) {
    $OutputPath = Join-Path -Path $scriptDir -ChildPath 'Output'
}
if (-not $PackageSourceOutputPath) {
    $PackageSourceOutputPath = Join-Path -Path $scriptDir -ChildPath 'PackageSources'
}

function Get-PharosPackageDefinition {
    <#
    .SYNOPSIS
    Reads selected Pharos package definitions.

    .PARAMETER DefinitionPath
    Root directory containing one folder per package.

    .PARAMETER SelectedPackageId
    Optional package IDs to return.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-07-27
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionPath,

        [Parameter()]
        [string[]]$SelectedPackageId
    )

    $definitionFile = Get-ChildItem -LiteralPath $DefinitionPath -Filter Package.json -File -Recurse
    $definitions = foreach ($file in $definitionFile) {
        $definition = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        $definition | Add-Member -NotePropertyName DefinitionFile -NotePropertyValue $file.FullName -PassThru
    }

    if ($SelectedPackageId) {
        $definitions = @($definitions | Where-Object { $_.PackageId -in $SelectedPackageId })
        $missingPackageId = @($SelectedPackageId | Where-Object { $_ -notin $definitions.PackageId })
        if ($missingPackageId.Count -gt 0) {
            throw "No definition was found for: $($missingPackageId -join ', ')"
        }
    }

    return @($definitions | Sort-Object -Property PackageId)
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

function Test-PharosPackageDefinition {
    <#
    .SYNOPSIS
    Validates one definition and its source installer payloads.

    .PARAMETER Definition
    Parsed package definition.

    .PARAMETER InstallerPath
    Source directory containing the vendor EXEs.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-07-27
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory)]
        [string]$InstallerPath
    )

    foreach ($propertyName in 'PackageId', 'DisplayName', 'Version', 'Installers', 'ExpectedPrinters') {
        if (-not $Definition.PSObject.Properties[$propertyName]) {
            throw "'$($Definition.DefinitionFile)' is missing '$propertyName'."
        }
    }

    if ($Definition.PackageId -notmatch '^[A-Za-z0-9-]+$') {
        throw "PackageId '$($Definition.PackageId)' contains unsupported characters."
    }

    foreach ($installer in @($Definition.Installers)) {
        $installerFilePath = Join-Path -Path $InstallerPath -ChildPath $installer.FileName
        if (-not (Test-Path -LiteralPath $installerFilePath -PathType Leaf)) {
            throw "Source installer was not found: $installerFilePath"
        }

        $actualHash = Get-PharosFileHash -Path $installerFilePath
        if ($actualHash -ne $installer.Sha256) {
            throw "SHA-256 mismatch for '$($installer.FileName)'. Expected $($installer.Sha256); found $actualHash."
        }
    }
}

function New-PharosStagingDirectory {
    <#
    .SYNOPSIS
    Creates a uniquely named temporary package staging directory.

    .PARAMETER PackageName
    Package ID used in the temporary folder name.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-07-27
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName
    )

    $stagingPath = Join-Path -Path $script:packageStagingRoot -ChildPath ('{0}-{1}' -f $PackageName, [guid]::NewGuid().ToString('N'))
    if ($PSCmdlet.ShouldProcess($stagingPath, 'Create temporary package staging directory')) {
        New-Item -Path $stagingPath -ItemType Directory -Force | Out-Null
    }

    return $stagingPath
}

function Remove-PharosStagingDirectory {
    <#
    .SYNOPSIS
    Removes a validated Pharos temporary staging directory.

    .PARAMETER Path
    Exact staging directory to remove.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-07-27
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $temporaryRoot = [System.IO.Path]::GetFullPath($script:packageStagingRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $resolvedTarget = [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $expectedPrefix = $temporaryRoot + [System.IO.Path]::DirectorySeparatorChar

    if (-not $resolvedTarget.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove staging path outside '$temporaryRoot': $resolvedTarget"
    }

    if ((Test-Path -LiteralPath $resolvedTarget) -and $PSCmdlet.ShouldProcess($resolvedTarget, 'Remove temporary package staging directory')) {
        Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
    }
}

function Export-PharosPackageSource {
    <#
    .SYNOPSIS
    Creates one package-ready Pharos source folder.

    .PARAMETER Definition
    Validated package definition.

    .PARAMETER InstallerPath
    Source vendor installer directory.

    .PARAMETER ScriptSourcePath
    Directory containing shared install and uninstall scripts.

    .PARAMETER DestinationRoot
    Root directory for per-location source folders.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-07-27
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory)]
        [string]$InstallerPath,

        [Parameter(Mandatory)]
        [string]$ScriptSourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationRoot
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($DestinationRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $destinationPath = Join-Path -Path $resolvedRoot -ChildPath $Definition.PackageId
    $resolvedDestination = [System.IO.Path]::GetFullPath($destinationPath)
    $expectedPrefix = $resolvedRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedDestination.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to stage a package outside '$resolvedRoot': $resolvedDestination"
    }

    if (-not $PSCmdlet.ShouldProcess($resolvedDestination, 'Create package-ready source folder')) {
        return
    }

    if (Test-Path -LiteralPath $resolvedDestination) {
        Remove-Item -LiteralPath $resolvedDestination -Recurse -Force
    }
    New-Item -Path $resolvedDestination -ItemType Directory -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path -Path $ScriptSourcePath -ChildPath 'Install-PharosLocation.ps1') -Destination $resolvedDestination
    Copy-Item -LiteralPath (Join-Path -Path $ScriptSourcePath -ChildPath 'Uninstall-PharosLocation.ps1') -Destination $resolvedDestination
    Copy-Item -LiteralPath $Definition.DefinitionFile -Destination (Join-Path -Path $resolvedDestination -ChildPath 'Package.json')

    foreach ($installer in @($Definition.Installers)) {
        Copy-Item -LiteralPath (Join-Path -Path $InstallerPath -ChildPath $installer.FileName) -Destination $resolvedDestination
    }

    $sourceSize = (Get-ChildItem -LiteralPath $resolvedDestination -File | Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{
        PackageId      = $Definition.PackageId
        SourcePath     = $resolvedDestination
        InstallerCount = @($Definition.Installers).Count
        SizeMB         = [math]::Round($sourceSize / 1MB, 2)
    }
}

function New-PharosIntunePackage {
    <#
    .SYNOPSIS
    Stages and builds one Pharos .intunewin package.

    .PARAMETER Definition
    Validated package definition.

    .PARAMETER InstallerPath
    Source vendor installer directory.

    .PARAMETER ScriptSourcePath
    Directory containing shared install and uninstall scripts.

    .PARAMETER PrepToolPath
    Path to IntuneWinAppUtil.exe.

    .PARAMETER DestinationPath
    Directory for final .intunewin files.

    .NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-07-27
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory)]
        [string]$InstallerPath,

        [Parameter(Mandatory)]
        [string]$ScriptSourcePath,

        [Parameter(Mandatory)]
        [string]$PrepToolPath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $packageFileName = 'Pharos-{0}-{1}.intunewin' -f $Definition.PackageId, $Definition.Version
    $destinationFile = Join-Path -Path $DestinationPath -ChildPath $packageFileName
    if (-not $PSCmdlet.ShouldProcess($destinationFile, 'Build Intune Win32 package')) {
        return
    }

    $stagingRoot = New-PharosStagingDirectory -PackageName $Definition.PackageId -Confirm:$false
    try {
        $contentPath = Join-Path -Path $stagingRoot -ChildPath 'Content'
        $rawOutputPath = Join-Path -Path $stagingRoot -ChildPath 'Output'
        New-Item -Path $contentPath, $rawOutputPath -ItemType Directory -Force | Out-Null

        Copy-Item -LiteralPath (Join-Path -Path $ScriptSourcePath -ChildPath 'Install-PharosLocation.ps1') -Destination $contentPath
        Copy-Item -LiteralPath (Join-Path -Path $ScriptSourcePath -ChildPath 'Uninstall-PharosLocation.ps1') -Destination $contentPath
        Copy-Item -LiteralPath $Definition.DefinitionFile -Destination (Join-Path -Path $contentPath -ChildPath 'Package.json')

        foreach ($installer in @($Definition.Installers)) {
            Copy-Item -LiteralPath (Join-Path -Path $InstallerPath -ChildPath $installer.FileName) -Destination $contentPath
        }

        & $PrepToolPath `
            -c $contentPath `
            -s 'Install-PharosLocation.ps1' `
            -o $rawOutputPath `
            -q 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "IntuneWinAppUtil failed for '$($Definition.PackageId)' with exit code $LASTEXITCODE."
        }

        $generatedFile = @(Get-ChildItem -LiteralPath $rawOutputPath -Filter '*.intunewin' -File)
        if ($generatedFile.Count -ne 1) {
            throw "Expected one generated .intunewin file for '$($Definition.PackageId)'; found $($generatedFile.Count)."
        }

        if (-not (Test-Path -LiteralPath $DestinationPath)) {
            New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        }
        Copy-Item -LiteralPath $generatedFile[0].FullName -Destination $destinationFile -Force

        [PSCustomObject]@{
            PackageId = $Definition.PackageId
            File      = $destinationFile
            SizeMB    = [math]::Round((Get-Item -LiteralPath $destinationFile).Length / 1MB, 2)
        }
    }
    finally {
        Remove-PharosStagingDirectory -Path $stagingRoot -Confirm:$false
    }
}

try {
    foreach ($requiredScript in 'Install-PharosLocation.ps1', 'Uninstall-PharosLocation.ps1') {
        $requiredScriptPath = Join-Path -Path $sourceScriptRoot -ChildPath $requiredScript
        if (-not (Test-Path -LiteralPath $requiredScriptPath -PathType Leaf)) {
            throw "Required source script was not found: $requiredScriptPath"
        }
    }

    if (-not (Test-Path -LiteralPath $InstallerSourcePath -PathType Container)) {
        throw "Installer source directory was not found: $InstallerSourcePath"
    }

    if (-not $ValidateOnly -and -not $StageOnly -and -not (Test-Path -LiteralPath $IntuneWinAppUtilPath -PathType Leaf)) {
        throw "IntuneWinAppUtil.exe was not found: $IntuneWinAppUtilPath"
    }

    $definitions = Get-PharosPackageDefinition -DefinitionPath $definitionRoot -SelectedPackageId $PackageId
    foreach ($definition in $definitions) {
        Test-PharosPackageDefinition -Definition $definition -InstallerPath $InstallerSourcePath
        Write-Output "Validated $($definition.PackageId) $($definition.Version)."
    }

    if ($ValidateOnly) {
        Write-Output "Validation succeeded for $($definitions.Count) package definition(s)."
        exit 0
    }

    if ($StageOnly) {
        $stagedSources = foreach ($definition in $definitions) {
            Export-PharosPackageSource `
                -Definition $definition `
                -InstallerPath $InstallerSourcePath `
                -ScriptSourcePath $sourceScriptRoot `
                -DestinationRoot $PackageSourceOutputPath `
                -WhatIf:$WhatIfPreference
        }
        $stagedSources | Format-Table -AutoSize
        exit 0
    }

    $results = foreach ($definition in $definitions) {
        New-PharosIntunePackage `
            -Definition $definition `
            -InstallerPath $InstallerSourcePath `
            -ScriptSourcePath $sourceScriptRoot `
            -PrepToolPath $IntuneWinAppUtilPath `
            -DestinationPath $OutputPath `
            -WhatIf:$WhatIfPreference
    }

    $results | Format-Table -AutoSize
    exit 0
}
catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
