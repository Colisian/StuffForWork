<#
.SYNOPSIS
    Restores the account-picture files and policy that existed before install.

.DESCRIPTION
    Reads the rollback state created by Install-LoginScreenAccountPicture.ps1.
    Each managed image is restored only when its current SHA-256 hash matches
    the hash deployed by this package. If a later tool changed a managed file,
    uninstall fails safely instead of overwriting that external change.

.NOTES
    Author  : Oji McLeod, UMD Libraries
    Date    : 2026-08-01
    Version : 1.0.0
    Context : SYSTEM, 64-bit Windows PowerShell 5.1 or later
    Log     : C:\ProgramData\UMDLibraries\LoginScreenAccountPicture\Uninstall-LoginScreenAccountPicture.log
    Exit 0  : Success
    Exit 1  : Failure or rollback conflict
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param()

begin {
    $ErrorActionPreference = 'Stop'

    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $componentRoot = Join-Path -Path $env:ProgramData -ChildPath 'UMDLibraries\LoginScreenAccountPicture'
    $stateRoot = Join-Path -Path $componentRoot -ChildPath 'State'
    $backupRoot = Join-Path -Path $stateRoot -ChildPath 'Backup'
    $rollbackPath = Join-Path -Path $stateRoot -ChildPath 'rollback.json'
    $script:logPath = Join-Path -Path $componentRoot -ChildPath 'Uninstall-LoginScreenAccountPicture.log'
    $pictureRoot = Join-Path -Path $env:ProgramData -ChildPath 'Microsoft\User Account Pictures'
    $policyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $policyName = 'UseDefaultTile'
    $sentinelPath = 'HKLM:\SOFTWARE\UMDLibraries\Intune\LoginScreenAccountPicture'

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
}

process {
    $exitCode = 0

    try {
        if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
            throw 'Run this uninstaller in 64-bit PowerShell. In Intune, set Run script as 32-bit process on 64-bit clients to No.'
        }

        if (-not (Test-Path -LiteralPath $componentRoot)) {
            New-Item -Path $componentRoot -ItemType Directory -Force | Out-Null
        }

        Write-Log "Starting rollback from package content directory: $ScriptDir"

        if (-not (Test-Path -LiteralPath $rollbackPath -PathType Leaf)) {
            throw "Rollback state is missing: $rollbackPath. Refusing to remove Windows default images without a recoverable baseline."
        }

        try {
            $rollbackState = Get-Content -LiteralPath $rollbackPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if ($rollbackState.SchemaVersion -ne 1) {
                throw "Unsupported rollback schema '$($rollbackState.SchemaVersion)'."
            }
        }
        catch {
            throw "Rollback state is unreadable: $($_.Exception.Message)"
        }

        foreach ($fileState in $rollbackState.Files) {
            if ($fileState.Name -notmatch '^user(?:-\d+)?\.(?:png|jpg|bmp)$') {
                throw "Unsafe file name in rollback state: '$($fileState.Name)'."
            }

            $targetPath = Join-Path -Path $pictureRoot -ChildPath $fileState.Name
            $deployedHashProperty = $rollbackState.DeployedHashes.PSObject.Properties[$fileState.Name]
            if (-not $deployedHashProperty) {
                throw "Rollback state has no deployed hash for '$($fileState.Name)'."
            }

            if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
                $currentHash = Get-Sha256Hash -LiteralPath $targetPath
                if ($currentHash -ne [string]$deployedHashProperty.Value) {
                    throw "Rollback conflict: '$targetPath' was changed after this app installed it. The file was left untouched."
                }
            }
            elseif ([bool]$fileState.Existed) {
                throw "Rollback conflict: '$targetPath' is missing, but an original file must be restored."
            }

            if ([bool]$fileState.Existed) {
                $backupPath = [string]$fileState.BackupPath
                if (-not $backupPath.StartsWith($backupRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "Unsafe backup path in rollback state: '$backupPath'."
                }
                if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
                    throw "Required backup is missing: $backupPath"
                }
                if ($PSCmdlet.ShouldProcess($targetPath, "Restore original from '$backupPath'")) {
                    Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force
                }
                Write-Log "Restored original $($fileState.Name)."
            }
            elseif (Test-Path -LiteralPath $targetPath -PathType Leaf) {
                if ($PSCmdlet.ShouldProcess($targetPath, 'Remove package-created account picture')) {
                    Remove-Item -LiteralPath $targetPath -Force
                }
                Write-Log "Removed package-created $($fileState.Name)."
            }
        }

        if ([bool]$rollbackState.Policy.Existed) {
            if (-not (Test-Path -LiteralPath $policyPath)) {
                New-Item -Path $policyPath -Force | Out-Null
            }
            if ($PSCmdlet.ShouldProcess("$policyPath\$policyName", 'Restore original registry value')) {
                Set-ItemProperty -LiteralPath $policyPath -Name $policyName -Value $rollbackState.Policy.Value -Force
            }
            Write-Log "Restored the previous $policyName policy value."
        }
        elseif (Test-Path -LiteralPath $policyPath) {
            $policyKey = Get-Item -LiteralPath $policyPath
            if ($policyKey.GetValueNames() -contains $policyName) {
                if ($PSCmdlet.ShouldProcess("$policyPath\$policyName", 'Remove package-created registry value')) {
                    Remove-ItemProperty -LiteralPath $policyPath -Name $policyName -Force
                }
                Write-Log "Removed the package-created $policyName policy value."
            }
        }

        if (Test-Path -LiteralPath $sentinelPath) {
            if ($PSCmdlet.ShouldProcess($sentinelPath, 'Remove the Intune detection sentinel')) {
                Remove-Item -LiteralPath $sentinelPath -Force
            }
        }

        if ($PSCmdlet.ShouldProcess($stateRoot, 'Remove rollback state after successful restoration')) {
            Remove-Item -LiteralPath $stateRoot -Recurse -Force
        }

        Write-Log 'Uninstall completed successfully. The restored tile appears after sign-out or restart.'
    }
    catch {
        $exitCode = 1
        Write-Log -Message "Uninstall failed: $($_.Exception.Message)" -Level 'ERROR'
        Write-Log -Message $_.InvocationInfo.PositionMessage -Level 'ERROR'
    }

    Write-Log "Exiting with code $exitCode."
    exit $exitCode
}
