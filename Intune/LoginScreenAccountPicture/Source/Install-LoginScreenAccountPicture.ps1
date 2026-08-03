<#
.SYNOPSIS
    Installs the UMD Libraries default Windows account picture.

.DESCRIPTION
    Intended for an Intune Win32 app running as SYSTEM. The script validates the
    bundled 448x448 and 192x192 PNG files, backs up the existing Windows default
    account-picture files, creates all sizes used by Windows, enables the
    machine-wide default-account-picture policy, and writes a registry sentinel.

    The companion image files are located with PSScriptRoot when the script is
    run from the package, or the current working directory when Intune runs the
    Win32 PowerShell script installer from unpacked content.

.PARAMETER Version
    Package version written to the detection sentinel.

.NOTES
    Author  : Oji McLeod, UMD Libraries
    Date    : 2026-08-01
    Version : 1.0.0
    Context : SYSTEM, 64-bit Windows PowerShell 5.1 or later
    Log     : C:\ProgramData\UMDLibraries\LoginScreenAccountPicture\Install-LoginScreenAccountPicture.log
    Exit 0  : Success
    Exit 1  : Failure
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Version = '1.0.0'
)

begin {
    $ErrorActionPreference = 'Stop'

    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $componentRoot = Join-Path -Path $env:ProgramData -ChildPath 'UMDLibraries\LoginScreenAccountPicture'
    $stateRoot = Join-Path -Path $componentRoot -ChildPath 'State'
    $backupRoot = Join-Path -Path $stateRoot -ChildPath 'Backup'
    $rollbackPath = Join-Path -Path $stateRoot -ChildPath 'rollback.json'
    $script:logPath = Join-Path -Path $componentRoot -ChildPath 'Install-LoginScreenAccountPicture.log'
    $pictureRoot = Join-Path -Path $env:ProgramData -ChildPath 'Microsoft\User Account Pictures'
    $policyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $policyName = 'UseDefaultTile'
    $sentinelPath = 'HKLM:\SOFTWARE\UMDLibraries\Intune\LoginScreenAccountPicture'
    $source448 = Join-Path -Path $ScriptDir -ChildPath 'UMD-AccountPicture-448.png'
    $source192 = Join-Path -Path $ScriptDir -ChildPath 'UMD-AccountPicture-192.png'
    $expectedSource448Hash = 'DD14AF03BD21A8DE84A0A74A34C314F685EDF0D274E4CD16B8102A3170D7B3DC'
    $expectedSource192Hash = '6E41A2907CDE32B03A11653B6B908B585B175CE4DDEE1C8E8EDE013764BB018F'

    function Write-Log {
        <#
        .SYNOPSIS
            Writes a timestamped deployment log entry.
        .PARAMETER Message
            Text to write.
        .PARAMETER Level
            INFO, WARN, or ERROR severity.
        .NOTES
            Author: Oji McLeod | Date: 2026-08-01 | Version: 1.0.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Message,

            [Parameter()]
            [ValidateSet('INFO', 'WARN', 'ERROR')]
            [string]$Level = 'INFO'
        )

        $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Write-Output $line
        try {
            Add-Content -LiteralPath $script:logPath -Value $line -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Verbose "Unable to append to '$script:logPath': $($_.Exception.Message)"
        }
    }

    function Get-Sha256Hash {
        <#
        .SYNOPSIS
            Returns the SHA-256 hash for a file.
        .PARAMETER LiteralPath
            Exact file path to hash.
        .NOTES
            Author: Oji McLeod | Date: 2026-08-01 | Version: 1.0.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$LiteralPath
        )

        return (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256 -ErrorAction Stop).Hash
    }

    function Export-ImageVariant {
        <#
        .SYNOPSIS
            Creates an exact-size account-picture file from a source image.
        .PARAMETER SourcePath
            Source PNG file.
        .PARAMETER DestinationPath
            Destination image path.
        .PARAMETER Width
            Output width in pixels.
        .PARAMETER Height
            Output height in pixels.
        .PARAMETER Format
            PNG, JPEG, or BMP output format.
        .NOTES
            Author: Oji McLeod | Date: 2026-08-01 | Version: 1.0.0
        #>
        [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
        param(
            [Parameter(Mandatory)]
            [string]$SourcePath,

            [Parameter(Mandatory)]
            [string]$DestinationPath,

            [Parameter(Mandatory)]
            [ValidateRange(1, 4096)]
            [int]$Width,

            [Parameter(Mandatory)]
            [ValidateRange(1, 4096)]
            [int]$Height,

            [Parameter(Mandatory)]
            [ValidateSet('PNG', 'JPEG', 'BMP')]
            [string]$Format
        )

        if (-not $PSCmdlet.ShouldProcess($DestinationPath, "Create $Width x $Height $Format image")) {
            return
        }

        Add-Type -AssemblyName System.Drawing
        $sourceImage = $null
        $bitmap = $null
        $graphics = $null
        $temporaryPath = '{0}.{1}.tmp' -f $DestinationPath, ([guid]::NewGuid().ToString('N'))

        try {
            $sourceImage = [System.Drawing.Image]::FromFile($SourcePath)
            $bitmap = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.Clear([System.Drawing.Color]::FromArgb(35, 36, 40))
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.DrawImage($sourceImage, 0, 0, $Width, $Height)

            $imageFormat = switch ($Format) {
                'PNG'  { [System.Drawing.Imaging.ImageFormat]::Png }
                'JPEG' { [System.Drawing.Imaging.ImageFormat]::Jpeg }
                'BMP'  { [System.Drawing.Imaging.ImageFormat]::Bmp }
            }

            $bitmap.Save($temporaryPath, $imageFormat)
            Move-Item -LiteralPath $temporaryPath -Destination $DestinationPath -Force
        }
        finally {
            if ($graphics) { $graphics.Dispose() }
            if ($bitmap) { $bitmap.Dispose() }
            if ($sourceImage) { $sourceImage.Dispose() }
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

process {
    $exitCode = 0

    try {
        if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
            throw 'Run this installer in 64-bit PowerShell. In Intune, set Run script as 32-bit process on 64-bit clients to No.'
        }

        foreach ($directory in @($componentRoot, $stateRoot, $backupRoot)) {
            if (-not (Test-Path -LiteralPath $directory)) {
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
            }
        }

        Write-Log "Starting UMD Libraries Login Screen Account Picture v$Version as $([Security.Principal.WindowsIdentity]::GetCurrent().Name)."
        Write-Log "Package content directory: $ScriptDir"

        foreach ($source in @(
                [pscustomobject]@{ Path = $source448; Hash = $expectedSource448Hash; Width = 448; Height = 448 },
                [pscustomobject]@{ Path = $source192; Hash = $expectedSource192Hash; Width = 192; Height = 192 }
            )) {
            if (-not (Test-Path -LiteralPath $source.Path -PathType Leaf)) {
                throw "Bundled image is missing: $($source.Path)"
            }

            if ((Get-Sha256Hash -LiteralPath $source.Path) -ne $source.Hash) {
                throw "Bundled image failed SHA-256 validation: $($source.Path)"
            }

            Add-Type -AssemblyName System.Drawing
            $validationImage = [System.Drawing.Image]::FromFile($source.Path)
            try {
                if ($validationImage.Width -ne $source.Width -or $validationImage.Height -ne $source.Height) {
                    throw "Bundled image '$($source.Path)' is $($validationImage.Width)x$($validationImage.Height); expected $($source.Width)x$($source.Height)."
                }
            }
            finally {
                $validationImage.Dispose()
            }
        }

        if (-not (Test-Path -LiteralPath $pictureRoot -PathType Container)) {
            throw "Windows account-picture directory was not found: $pictureRoot"
        }

        $targetDefinitions = @(
            [pscustomobject]@{ Name = 'user.png'; Source = $source448; Width = 448; Height = 448; Format = 'PNG'; CopyExact = $true },
            [pscustomobject]@{ Name = 'user.jpg'; Source = $source448; Width = 448; Height = 448; Format = 'JPEG'; CopyExact = $false },
            [pscustomobject]@{ Name = 'user.bmp'; Source = $source448; Width = 448; Height = 448; Format = 'BMP'; CopyExact = $false },
            [pscustomobject]@{ Name = 'user-192.png'; Source = $source192; Width = 192; Height = 192; Format = 'PNG'; CopyExact = $true },
            [pscustomobject]@{ Name = 'user-48.png'; Source = $source192; Width = 48; Height = 48; Format = 'PNG'; CopyExact = $false },
            [pscustomobject]@{ Name = 'user-40.png'; Source = $source192; Width = 40; Height = 40; Format = 'PNG'; CopyExact = $false },
            [pscustomobject]@{ Name = 'user-32.png'; Source = $source192; Width = 32; Height = 32; Format = 'PNG'; CopyExact = $false }
        )

        if (Test-Path -LiteralPath $rollbackPath -PathType Leaf) {
            try {
                $rollbackState = Get-Content -LiteralPath $rollbackPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
                if ($rollbackState.SchemaVersion -ne 1) {
                    throw "Unsupported rollback schema '$($rollbackState.SchemaVersion)'."
                }
                Write-Log 'Existing rollback state found; preserving the original pre-install baseline.'
            }
            catch {
                throw "Existing rollback state is unreadable. Refusing to replace the backup: $($_.Exception.Message)"
            }
        }
        else {
            $fileState = foreach ($definition in $targetDefinitions) {
                $targetPath = Join-Path -Path $pictureRoot -ChildPath $definition.Name
                $backupPath = Join-Path -Path $backupRoot -ChildPath $definition.Name
                $existed = Test-Path -LiteralPath $targetPath -PathType Leaf

                if ($existed -and $PSCmdlet.ShouldProcess($targetPath, "Back up to '$backupPath'")) {
                    Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force
                }

                [pscustomobject]@{
                    Name       = $definition.Name
                    Existed    = $existed
                    BackupPath = $backupPath
                }
            }

            $policyValueExists = $false
            $policyValue = $null
            $policyKind = $null
            if (Test-Path -LiteralPath $policyPath) {
                $policyKey = Get-Item -LiteralPath $policyPath
                if ($policyKey.GetValueNames() -contains $policyName) {
                    $policyValueExists = $true
                    $policyValue = $policyKey.GetValue($policyName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    $policyKind = $policyKey.GetValueKind($policyName).ToString()
                }
            }

            $rollbackState = [pscustomobject]@{
                SchemaVersion    = 1
                PackageVersion   = $Version
                BackupCreatedUtc = (Get-Date).ToUniversalTime().ToString('o')
                Files            = @($fileState)
                Policy           = [pscustomobject]@{
                    Existed = $policyValueExists
                    Value   = $policyValue
                    Kind    = $policyKind
                }
                DeployedHashes   = $null
            }

            if ($PSCmdlet.ShouldProcess($rollbackPath, 'Write rollback state')) {
                $temporaryRollbackPath = "$rollbackPath.tmp"
                $rollbackState | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryRollbackPath -Encoding UTF8 -Force
                Move-Item -LiteralPath $temporaryRollbackPath -Destination $rollbackPath -Force
            }
            Write-Log "Backed up the original Windows account pictures and policy state to $stateRoot."
        }

        foreach ($definition in $targetDefinitions) {
            $targetPath = Join-Path -Path $pictureRoot -ChildPath $definition.Name
            if ($definition.CopyExact) {
                if ($PSCmdlet.ShouldProcess($targetPath, "Copy '$($definition.Source)'")) {
                    $temporaryTarget = '{0}.{1}.tmp' -f $targetPath, ([guid]::NewGuid().ToString('N'))
                    Copy-Item -LiteralPath $definition.Source -Destination $temporaryTarget -Force
                    Move-Item -LiteralPath $temporaryTarget -Destination $targetPath -Force
                }
            }
            else {
                Export-ImageVariant -SourcePath $definition.Source -DestinationPath $targetPath -Width $definition.Width -Height $definition.Height -Format $definition.Format -Confirm:$false
            }
            Write-Log "Installed $($definition.Name) ($($definition.Width)x$($definition.Height), $($definition.Format))."
        }

        if (-not (Test-Path -LiteralPath $policyPath)) {
            New-Item -Path $policyPath -Force | Out-Null
        }
        if ($PSCmdlet.ShouldProcess("$policyPath\$policyName", 'Enable the machine-wide default account picture')) {
            Set-ItemProperty -LiteralPath $policyPath -Name $policyName -Value 1 -Force
        }

        $deployedHashes = [ordered]@{}
        foreach ($definition in $targetDefinitions) {
            $targetPath = Join-Path -Path $pictureRoot -ChildPath $definition.Name
            $deployedHashes[$definition.Name] = Get-Sha256Hash -LiteralPath $targetPath
        }

        $rollbackState.PackageVersion = $Version
        $rollbackState.DeployedHashes = [pscustomobject]$deployedHashes
        if ($PSCmdlet.ShouldProcess($rollbackPath, 'Update rollback state with installed file hashes')) {
            $temporaryRollbackPath = "$rollbackPath.tmp"
            $rollbackState | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryRollbackPath -Encoding UTF8 -Force
            Move-Item -LiteralPath $temporaryRollbackPath -Destination $rollbackPath -Force
        }

        if (-not (Test-Path -LiteralPath $sentinelPath)) {
            New-Item -Path $sentinelPath -Force | Out-Null
        }
        Set-ItemProperty -LiteralPath $sentinelPath -Name 'Version' -Value $Version -Force
        Set-ItemProperty -LiteralPath $sentinelPath -Name 'InstalledUtc' -Value ((Get-Date).ToUniversalTime().ToString('o')) -Force
        Set-ItemProperty -LiteralPath $sentinelPath -Name 'Source448Sha256' -Value $expectedSource448Hash -Force
        Set-ItemProperty -LiteralPath $sentinelPath -Name 'Source192Sha256' -Value $expectedSource192Hash -Force
        Set-ItemProperty -LiteralPath $sentinelPath -Name 'TargetHashesJson' -Value (($deployedHashes | ConvertTo-Json -Compress)) -Force
        Set-ItemProperty -LiteralPath $sentinelPath -Name 'InstallComplete' -Value 1 -Force

        if ((Get-ItemPropertyValue -LiteralPath $policyPath -Name $policyName) -ne 1) {
            throw 'Post-install verification failed: UseDefaultTile is not enabled.'
        }
        foreach ($definition in $targetDefinitions) {
            $targetPath = Join-Path -Path $pictureRoot -ChildPath $definition.Name
            if ((Get-Sha256Hash -LiteralPath $targetPath) -ne $deployedHashes[$definition.Name]) {
                throw "Post-install verification failed for $targetPath."
            }
        }

        Write-Log 'Installation completed successfully. The new tile appears after sign-out or restart.'
    }
    catch {
        $exitCode = 1
        Write-Log -Message "Installation failed: $($_.Exception.Message)" -Level 'ERROR'
        Write-Log -Message $_.InvocationInfo.PositionMessage -Level 'ERROR'
    }

    Write-Log "Exiting with code $exitCode."
    exit $exitCode
}
