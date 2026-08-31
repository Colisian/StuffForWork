<#
.SYNOPSIS
    Restores the lock-screen policy changed by Library Sign-In Background.

.DESCRIPTION
    Intended for an Intune Win32 app running as SYSTEM. It restores the prior
    LockScreenImage policy only if this app still owns the configured path.

.NOTES
    Author  : Oji McLeod, UMD Libraries
    Date    : 2026-08-29
    Version : 1.0.3
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param()

begin {
    $ErrorActionPreference = 'Stop'
    $componentRoot = Join-Path $env:ProgramData 'UMDLibraries\LibrarySignInBackground'
    $statePath = Join-Path $componentRoot 'State\rollback.json'
    $sentinelPath = 'HKLM:\SOFTWARE\UMDLibraries\Intune\LibrarySignInBackground'
    $personalizationPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
    $logPath = Join-Path $componentRoot 'Uninstall-LibrarySignInBackground.log'

    function Write-Log {
        <#
        .SYNOPSIS
            Writes a timestamped message to the uninstall log and pipeline.
        .NOTES
            Author: Oji McLeod | Date: 2026-08-29 | Version: 1.0.3
        #>
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$Message)
        $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Write-Output $line
        Add-Content -LiteralPath $script:logPath -Value $line -Encoding UTF8
    }
}

process {
    try {
        if (-not (Test-Path -LiteralPath $sentinelPath)) { exit 0 }
        $sentinel = Get-ItemProperty -LiteralPath $sentinelPath
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $current = if (Test-Path -LiteralPath $personalizationPath) {
            (Get-ItemProperty -LiteralPath $personalizationPath).LockScreenImage
        }
        if ($current -ne $sentinel.ImagePath) { throw 'LockScreenImage is now managed by another configuration; refusing to overwrite it.' }
        if (-not $PSCmdlet.ShouldProcess($sentinel.ImagePath, 'Restore the previous lock-screen setting')) { return }

        if ($state.PriorLockScreenImageExists) {
            Set-ItemProperty -LiteralPath $personalizationPath -Name 'LockScreenImage' -Value $state.PriorLockScreenImage -Type String -Force
        }
        else {
            Remove-ItemProperty -LiteralPath $personalizationPath -Name 'LockScreenImage' -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $sentinelPath -Recurse -Force
        Write-Log 'Restored the prior LockScreenImage policy. The generated image and logs remain in ProgramData for audit.'
        exit 0
    }
    catch {
        if (Test-Path -LiteralPath $componentRoot) { Write-Log "ERROR: $($_.Exception.Message)" }
        else { Write-Error $_ }
        exit 1
    }
}
