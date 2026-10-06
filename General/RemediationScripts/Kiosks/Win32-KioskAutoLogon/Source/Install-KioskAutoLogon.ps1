<#
.SYNOPSIS
Repairs the existing local kiosk account's automatic logon for Intune Win32 deployment.
.NOTES
Author: UMD Libraries IT / Oji. Date: 2026-10-06. Version: 1.2.0.
Requires Windows PowerShell 5.1, 64-bit Windows, and SYSTEM or an administrator.
#>
[CmdletBinding(SupportsShouldProcess)]
param()
begin { $ErrorActionPreference = 'Stop' }
process {
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $logDir = 'C:\ProgramData\UMDLibraries\KioskAutoLogon\Logs'
    $markerPath = 'HKLM:\SOFTWARE\UMDLibraries\KioskAutoLogon'
    $winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $logStarted = $false
    try {
        if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell (Sysnative in Intune).' }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator or SYSTEM required.' }
        $config = Get-Content -LiteralPath (Join-Path $ScriptDir 'KioskConfig.json') -Raw | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace($config.UserName) -or [string]::IsNullOrWhiteSpace($config.DeploymentVersion)) { throw 'Missing username or deployment version.' }
        $startupSource = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\AxisTV Engage\Start AxisTV Engage Playback.lnk'
        $startupFolder = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonStartup)
        $startupShortcut = Join-Path $startupFolder 'Start AxisTV Engage Playback.lnk'
        if (-not (Test-Path -LiteralPath $startupShortcut -PathType Leaf) -and -not (Test-Path -LiteralPath $startupSource -PathType Leaf)) {
            Write-Output "Required AxisTV shortcut missing: $startupSource. Install AxisTV Engage before this app."
            throw 'AxisTV Engage shortcut missing.'
        }
        $localUser = Get-LocalUser -Name $config.UserName
        if (-not $localUser.Enabled) { throw 'The existing kiosk account is disabled. Enable it deliberately before deployment.' }
        if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Repair auto-logon for $($config.UserName)")) { return }
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Start-Transcript -Path (Join-Path $logDir 'Install-KioskAutoLogon.log') -Append | Out-Null
        $logStarted = $true
        $previousMarker = Get-ItemProperty -Path $markerPath -ErrorAction SilentlyContinue
        # Clear completion first so a failed repair cannot leave a successful marker.
        if (Test-Path $markerPath) { Remove-ItemProperty -Path $markerPath -Name 'DeploymentVersion' -ErrorAction SilentlyContinue }
        $credentialPath = Join-Path $ScriptDir $config.PasswordFile
        $password = [IO.File]::ReadAllText($credentialPath).TrimEnd([char[]]"`r`n")
        if ([string]::IsNullOrWhiteSpace($password)) { throw 'The bundled password file is empty.' }
        if (-not ('UMDLibraries.AutologonSecret' -as [type])) { Add-Type -Path (Join-Path $ScriptDir 'NativeAutologon.cs') }
        Set-LocalUser -Name $config.UserName -Password (ConvertTo-SecureString $password -AsPlainText -Force) -PasswordNeverExpires $true -AccountNeverExpires
        if ($config.RemoveDeviceLockPolicies -eq $true) {
            # Matches the original repair; assigned Intune policy can reapply these keys.
            $keys = @('HKLM:\SYSTEM\CurrentControlSet\Control\EAS', 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeviceLock')
            $accountPath = 'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts'
            if (Test-Path $accountPath) {
                foreach ($enrollment in Get-ChildItem $accountPath) {
                    $keys += "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$($enrollment.PSChildName)\default\Device\DeviceLock"
                }
            }
            foreach ($key in $keys) { if (Test-Path $key) { Remove-Item -Path $key -Recurse -Force } }
        }
        if (-not (Test-Path $winlogonPath)) { New-Item -Path $winlogonPath -Force | Out-Null }
        # Disable while updating, then enable only after the LSA password is stored.
        Set-ItemProperty -Path $winlogonPath -Name 'AutoAdminLogon' -Value '0' -Force
        [UMDLibraries.AutologonSecret]::Store($password)
        $password = $null
        foreach ($name in @('DefaultPassword', 'AutoLogonCount')) {
            if ((Get-Item $winlogonPath).GetValueNames() -contains $name) { Remove-ItemProperty -Path $winlogonPath -Name $name }
        }
        Set-ItemProperty -Path $winlogonPath -Name 'DefaultUserName' -Value ".\$($config.UserName)" -Force
        Set-ItemProperty -Path $winlogonPath -Name 'DefaultDomainName' -Value $env:COMPUTERNAME -Force
        Set-ItemProperty -Path $winlogonPath -Name 'AutoAdminLogon' -Value '1' -Force
        $settings = Get-ItemProperty $winlogonPath
        if ($settings.AutoAdminLogon -ne '1' -or $settings.DefaultUserName -ne ".\$($config.UserName)" -or -not [UMDLibraries.AutologonSecret]::Exists()) { throw 'Auto-logon verification failed.' }
        # Keep an existing original-name shortcut untouched, even if customized.
        New-Item -ItemType Directory -Path $startupFolder -Force | Out-Null
        $startupManaged = 0
        if (Test-Path -LiteralPath $startupShortcut -PathType Leaf) {
            $startupHash = (Get-FileHash -LiteralPath $startupShortcut -Algorithm SHA256).Hash
            if ($previousMarker.StartupShortcutName -eq 'Start AxisTV Engage Playback.lnk' -and $previousMarker.StartupShortcutManaged -eq 1 -and $previousMarker.StartupShortcutHash -eq $startupHash) {
                $startupManaged = 1
            }
            Write-Output "AxisTV startup shortcut already exists; preserved without copying: $startupShortcut"
        } else {
            Copy-Item -LiteralPath $startupSource -Destination $startupShortcut
            $startupHash = (Get-FileHash -LiteralPath $startupShortcut -Algorithm SHA256).Hash
            if ($startupHash -ne (Get-FileHash -LiteralPath $startupSource -Algorithm SHA256).Hash) { throw 'Startup shortcut verification failed.' }
            $startupManaged = 1
            Write-Output "Copied AxisTV playback shortcut with its original filename: $startupShortcut"
        }
        # Remove the earlier renamed copy to prevent two playback launches.
        $legacyShortcut = Join-Path $startupFolder 'UMD-AxisTV Engage Playback.lnk'
        if (Test-Path -LiteralPath $legacyShortcut -PathType Leaf) {
            $legacyHash = (Get-FileHash -LiteralPath $legacyShortcut -Algorithm SHA256).Hash
            $sourceHash = if (Test-Path -LiteralPath $startupSource -PathType Leaf) { (Get-FileHash -LiteralPath $startupSource -Algorithm SHA256).Hash } else { $null }
            if ($legacyHash -eq $previousMarker.StartupShortcutHash -or $legacyHash -eq $sourceHash -or $legacyHash -eq $startupHash) {
                Remove-Item -LiteralPath $legacyShortcut -Force
                Write-Output 'Removed earlier UMD-AxisTV Engage Playback.lnk startup copy to prevent duplicate launches.'
            } else {
                Write-Output "Renamed startup copy differs from known copies; review and remove it manually: $legacyShortcut"
                throw 'Unrecognized duplicate AxisTV startup shortcut.'
            }
        }
        if (-not (Test-Path $markerPath)) { New-Item -Path $markerPath -Force | Out-Null }
        Set-ItemProperty -Path $markerPath -Name 'StartupShortcutName' -Value 'Start AxisTV Engage Playback.lnk' -Force
        Set-ItemProperty -Path $markerPath -Name 'StartupShortcutManaged' -Value $startupManaged -Force
        Set-ItemProperty -Path $markerPath -Name 'StartupShortcutHash' -Value $startupHash -Force
        Set-ItemProperty -Path $markerPath -Name 'UserName' -Value $config.UserName -Force
        Set-ItemProperty -Path $markerPath -Name 'InstalledUtc' -Value ([DateTime]::UtcNow.ToString('o')) -Force
        Set-ItemProperty -Path $markerPath -Name 'DeploymentVersion' -Value $config.DeploymentVersion -Force
        Write-Output 'Auto-logon repair completed. Takes effect at next sign-in/restart; no restart was initiated.'
        exit 0
    } catch {
        # Do not emit raw exceptions from credential operations or log a password.
        Write-Output "Kiosk auto-logon install failed. Error type: $($_.Exception.GetType().Name); line: $($_.InvocationInfo.ScriptLineNumber)."
        exit 1
    } finally {
        $password = $null
        if ($logStarted) { Stop-Transcript | Out-Null }
    }
}


