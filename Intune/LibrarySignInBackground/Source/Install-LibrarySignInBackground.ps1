<#
.SYNOPSIS
    Creates and applies the UMD Libraries lock and sign-in background.

.DESCRIPTION
    Intended for an Intune Win32 app running as SYSTEM. It uses the bundled,
    pinned PowerBGInfo module to create a per-device image containing the
    library sign-in instructions and computer name. The final image is applied
    as the local lock-screen/sign-in image and recorded for safe detection.

.NOTES
    Author  : Oji McLeod, UMD Libraries
    Date    : 2026-08-29
    Version : 1.0.2
    Context : SYSTEM, 64-bit Windows PowerShell 5.1 or later
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Version = '1.0.2'
)

begin {
    $ErrorActionPreference = 'Stop'
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $componentRoot = Join-Path $env:ProgramData 'UMDLibraries\LibrarySignInBackground'
    $stateRoot = Join-Path $componentRoot 'State'
    $logPath = Join-Path $componentRoot 'Install-LibrarySignInBackground.log'
    $statePath = Join-Path $stateRoot 'rollback.json'
    $finalImage = Join-Path $componentRoot 'Library-SignIn-Background.jpg'
    $intermediateImage = Join-Path $stateRoot 'SignIn-Text.jpg'
    # PowerShell 5.1 Expand-Archive accepts ZIP files only; this is the
    # unmodified PowerShell Gallery NUPKG payload renamed with a .zip extension.
    $modulePackage = Join-Path $ScriptDir 'PowerBGInfo.2.0.2.zip'
    $moduleRoot = Join-Path $componentRoot 'Modules\PowerBGInfo\2.0.2'
    $moduleManifest = Join-Path $moduleRoot 'PowerBGInfo.psd1'
    $requiredModuleFile = Join-Path $moduleRoot 'Lib\Default\ChartForgeX.dll'
    $expectedModuleHash = '036BAD03155983832EFC02C1E8B25798E89C7978CF50BB6B320393FB82DE75F0'
    $personalizationPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
    $systemPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    $sentinelPath = 'HKLM:\SOFTWARE\UMDLibraries\Intune\LibrarySignInBackground'

    function Write-Log {
        <#
        .SYNOPSIS
            Writes a timestamped message to the deployment log and pipeline.
        .NOTES
            Author: Oji McLeod | Date: 2026-08-29 | Version: 1.0.2
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
        if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
            throw 'Run this installer in 64-bit PowerShell. Set Intune Run script as 32-bit process on 64-bit clients to No.'
        }

        foreach ($path in @($componentRoot, $stateRoot)) {
            if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -ItemType Directory -Force | Out-Null }
        }
        Write-Log "Starting Library Sign-In Background v$Version as $([Security.Principal.WindowsIdentity]::GetCurrent().Name)."

        if (-not (Test-Path -LiteralPath $modulePackage -PathType Leaf)) {
            throw "Bundled PowerBGInfo package was not found: $modulePackage"
        }
        if ((Get-FileHash -LiteralPath $modulePackage -Algorithm SHA256).Hash -ne $expectedModuleHash) {
            throw "Bundled PowerBGInfo package failed SHA-256 validation: $modulePackage"
        }
        if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf) -or
            -not (Test-Path -LiteralPath $requiredModuleFile -PathType Leaf)) {
            if (Test-Path -LiteralPath $moduleRoot) { Remove-Item -LiteralPath $moduleRoot -Recurse -Force }
            New-Item -Path $moduleRoot -ItemType Directory -Force | Out-Null
            Expand-Archive -LiteralPath $modulePackage -DestinationPath $moduleRoot -Force
        }
        if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf) -or
            -not (Test-Path -LiteralPath $requiredModuleFile -PathType Leaf)) {
            throw "PowerBGInfo expansion is incomplete. Check endpoint-security events for '$requiredModuleFile'."
        }
        Import-Module -Name $moduleManifest -Force -ErrorAction Stop

        if ((Test-Path -LiteralPath $systemPolicyPath) -and
            ((Get-ItemProperty -LiteralPath $systemPolicyPath).DisableLogonBackgroundImage -eq 1)) {
            throw 'DisableLogonBackgroundImage is enabled by another policy. Remove that conflicting policy before deploying this app.'
        }

        if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
            $priorExists = $false
            $priorValue = $null
            if (Test-Path -LiteralPath $personalizationPath) {
                $prior = Get-ItemProperty -LiteralPath $personalizationPath
                $priorExists = $prior.PSObject.Properties.Name -contains 'LockScreenImage'
                if ($priorExists) { $priorValue = [string]$prior.LockScreenImage }
            }
            [pscustomobject]@{
                SchemaVersion = 1
                PriorLockScreenImageExists = $priorExists
                PriorLockScreenImage = $priorValue
            } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
        }

        if (-not $PSCmdlet.ShouldProcess($finalImage, 'Create and apply Library sign-in background')) { return }

        New-BGInfo -Target File -OutputFileName 'SignIn-Text.jpg' -ConfigurationDirectory $stateRoot `
            -BackgroundColor '#0078D7' -TextPosition TopLeft -SpaceX 105 -SpaceY 160 `
            -FontFamilyName 'Segoe UI' -FontSize 24 -FontWeight 600 -Color White `
            -SpaceBetweenLines 28 -DisableWallpaperSlideshow {
            New-BGInfoLabel -Name 'Logging ON? FOLLOW INSTRUCTIONS BELOW.'
            New-BGInfoLabel -Name 'User name: Directory ID (your email address without @umd.edu)'
            New-BGInfoLabel -Name 'Password: Password you use for logging into ELMS'
            New-BGInfoLabel -Name 'Visitors: Check at the desk to obtain a temporary Guest Account'
        } | Out-Null

        New-BGInfo -Target LogonScreen -FilePath $intermediateImage -OutputFileName (Split-Path $finalImage -Leaf) `
            -ConfigurationDirectory $componentRoot -TextPosition BottomCenter -SpaceY 145 `
            -FontFamilyName 'Segoe UI' -FontSize 24 -FontWeight 600 -Color White `
            -ValueFontFamilyName 'Segoe UI' -ValueFontSize 24 -ValueFontWeight 600 -ValueColor White `
            -SpaceBetweenColumns 12 -DisableWallpaperSlideshow {
            New-BGInfoValue -Name 'Computer Name:' -BuiltinValue HostName
        } | Out-Null

        if (-not (Test-Path -LiteralPath $finalImage -PathType Leaf)) { throw "PowerBGInfo did not create '$finalImage'." }
        if (-not (Test-Path -LiteralPath $personalizationPath)) { New-Item -Path $personalizationPath -Force | Out-Null }
        Set-ItemProperty -LiteralPath $personalizationPath -Name 'LockScreenImage' -Value $finalImage -Type String -Force

        $hash = (Get-FileHash -LiteralPath $finalImage -Algorithm SHA256).Hash
        if (-not (Test-Path -LiteralPath $sentinelPath)) { New-Item -Path $sentinelPath -Force | Out-Null }
        Set-ItemProperty -LiteralPath $sentinelPath -Name Version -Value $Version -Type String -Force
        Set-ItemProperty -LiteralPath $sentinelPath -Name ImagePath -Value $finalImage -Type String -Force
        Set-ItemProperty -LiteralPath $sentinelPath -Name ImageHash -Value $hash -Type String -Force
        Set-ItemProperty -LiteralPath $sentinelPath -Name InstallComplete -Value 1 -Type DWord -Force
        Write-Log "Created and applied '$finalImage' for $env:COMPUTERNAME."
        exit 0
    }
    catch {
        if (Test-Path -LiteralPath $componentRoot) { Write-Log "ERROR: $($_.Exception.Message)" }
        else { Write-Error $_ }
        exit 1
    }
}
