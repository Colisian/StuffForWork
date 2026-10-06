<#
.SYNOPSIS
Disables managed kiosk auto-logon without deleting the account or resetting its password.
.NOTES
Author: UMD Libraries IT / Oji. Date: 2026-10-06. Version: 1.1.0.
Does not restore deleted DeviceLock policies; Intune policy must reapply them.
#>
[CmdletBinding(SupportsShouldProcess)]
param()
begin { $ErrorActionPreference = 'Stop' }
process {
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $logStarted = $false
    try {
        if (-not [Environment]::Is64BitProcess) { throw '64-bit Windows PowerShell required.' }
        $markerPath = 'HKLM:\SOFTWARE\UMDLibraries\KioskAutoLogon'
        $winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
        $config = Get-Content -LiteralPath (Join-Path $ScriptDir 'KioskConfig.json') -Raw | ConvertFrom-Json
        $settings = Get-ItemProperty $winlogonPath
        # Protect another auto-logon account if the device was subsequently repurposed.
        if ($settings.DefaultUserName -and $settings.DefaultUserName -notin @($config.UserName, ".\$($config.UserName)")) { throw 'Another auto-logon account is configured; refusing to disable it.' }
        if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Disable kiosk automatic logon')) { return }
        $logDir = 'C:\ProgramData\UMDLibraries\KioskAutoLogon\Logs'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Start-Transcript -Path (Join-Path $logDir 'Uninstall-KioskAutoLogon.log') -Append | Out-Null
        $logStarted = $true
        if (-not ('UMDLibraries.AutologonSecret' -as [type])) { Add-Type -Path (Join-Path $ScriptDir 'NativeAutologon.cs') }
        Set-ItemProperty -Path $winlogonPath -Name 'AutoAdminLogon' -Value '0' -Force
        [UMDLibraries.AutologonSecret]::Store($null)
        foreach ($name in @('DefaultPassword', 'DefaultUserName', 'DefaultDomainName', 'AutoLogonCount')) {
            if ((Get-Item $winlogonPath).GetValueNames() -contains $name) { Remove-ItemProperty -Path $winlogonPath -Name $name }
        }
        $startupFolder = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonStartup)
        $startupShortcut = Join-Path $startupFolder 'UMD-AxisTV Engage Playback.lnk'
        if (Test-Path -LiteralPath $startupShortcut -PathType Leaf) {
            $marker = Get-ItemProperty -Path $markerPath -ErrorAction SilentlyContinue
            # Remove only an unchanged shortcut recorded by this deployment.
            if ($marker.StartupShortcutHash -and (Get-FileHash -LiteralPath $startupShortcut -Algorithm SHA256).Hash -eq $marker.StartupShortcutHash) {
                Remove-Item -LiteralPath $startupShortcut -Force
                Write-Output 'Removed managed AxisTV Startup shortcut.'
            } else {
                Write-Output 'Startup shortcut changed or has no ownership marker; retained for manual review.'
            }
        }
        if (Test-Path $markerPath) { Remove-Item -Path $markerPath -Recurse -Force }
        Write-Output 'Kiosk automatic logon disabled. Account and current session retained.'
        exit 0
    } catch {
        Write-Output "Kiosk uninstall failed. Error type: $($_.Exception.GetType().Name); line: $($_.InvocationInfo.ScriptLineNumber)."
        exit 1
    } finally { if ($logStarted) { Stop-Transcript | Out-Null } }
}

