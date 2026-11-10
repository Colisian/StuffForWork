<#
.SYNOPSIS
Removes registered SysAid Agent MSI products, including versions updated by SysAid.
.NOTES
Author: UMD Libraries IT / Codex
Date: 2026-11-10
Version: 1.0.0
Does not use WMIC or Win32_Product. Retains deployment logs for troubleshooting.
#>
[CmdletBinding(SupportsShouldProcess)]
param()
begin { $ErrorActionPreference = 'Stop' }
end {
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $result = 1
    $transcribing = $false
    try {
        if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
            $nativeArgs = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $ScriptDir 'Uninstall-SysAidAgent.ps1'))
            if ($WhatIfPreference) { $nativeArgs += '-WhatIf' }
            & "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" @nativeArgs
            $result = $LASTEXITCODE
            return
        }
        $products = @(foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
            if (Test-Path -LiteralPath $root) {
                Get-ChildItem -LiteralPath $root | Get-ItemProperty | Where-Object {
                    $_.DisplayName -eq 'SysAid Agent' -and $_.Publisher -match '^SysAid' -and $_.WindowsInstaller -eq 1 -and
                    $_.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$'
                }
            }
        })
        if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Uninstall registered SysAid Agent MSI products')) { return }
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as SYSTEM or elevated administrator.' }
        $logDir = 'C:\ProgramData\UMDLibraries\SysAid'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        & icacls.exe $logDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Unable to restrict the deployment log directory.' }
        Start-Transcript -Path (Join-Path $logDir 'Uninstall-SysAidAgent.log') -Append -Force | Out-Null
        $transcribing = $true
        $result = 0
        foreach ($product in $products) {
            $msiLog = Join-Path $logDir ('MSI-Uninstall-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
            $arguments = "/x $($product.PSChildName) /qn /norestart REBOOT=ReallySuppress /L* `"$msiLog`""
            $removal = Start-Process -FilePath "$env:WINDIR\System32\msiexec.exe" -ArgumentList $arguments -Wait -PassThru
            Write-Output "Windows Installer exit code: $($removal.ExitCode)"
            if ($removal.ExitCode -eq 1618) { $result = 1618; return }
            if ($removal.ExitCode -notin @(0, 1605, 1614, 3010)) { throw "MSI uninstall failed: $($removal.ExitCode)." }
            if ($removal.ExitCode -eq 3010) { $result = 3010 }
        }
        $service = Get-Service -Name 'SysAidAgent' -ErrorAction SilentlyContinue
        if ($service -and $result -ne 3010) { throw 'The SysAid service remains. Check for an EXE installation, uninstall protection, or incomplete removal.' }
        foreach ($product in $products) {
            if ((Test-Path -LiteralPath $product.PSPath) -and $result -ne 3010) { throw 'A SysAid MSI registration remains after uninstall.' }
        }
        $markerKey = 'HKLM:\SOFTWARE\UMDLibraries\SysAidAgent'
        if (Test-Path -LiteralPath $markerKey) { Remove-Item -LiteralPath $markerKey -Recurse -Force }
        Write-Output 'SysAid uninstall completed. Deployment logs were retained.'
    } catch { Write-Error $_ -ErrorAction Continue; $result = 1 }
    finally {
        if ($transcribing) { Stop-Transcript | Out-Null }
        if (-not $WhatIfPreference) { exit $result }
    }
}
