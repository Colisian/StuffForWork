<#
.SYNOPSIS
Installs the UMD Libraries SysAid agent silently as SYSTEM using its bundled MSI and MST.
.NOTES
Author: UMD Libraries IT / Codex
Date: 2026-11-10
Version: 1.0.0
Works as a packaged command or Intune PowerShell script installer. Supports -WhatIf.
#>
[CmdletBinding(SupportsShouldProcess)]
param()
begin { $ErrorActionPreference = 'Stop' }
end {
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $transcribing = $false
    $result = 1
    try {
        if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64' -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
            throw 'This package supports Windows x64 endpoints only.'
        }
        # Intune command lines can launch 32-bit PowerShell; re-enter the bundled script in native PowerShell.
        if (-not [Environment]::Is64BitProcess) {
            $nativeArgs = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $ScriptDir 'Install-SysAidAgent.ps1'))
            if ($WhatIfPreference) { $nativeArgs += '-WhatIf' }
            & "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" @nativeArgs
            $result = $LASTEXITCODE
            return
        }
        $config = Get-Content -LiteralPath (Join-Path $ScriptDir 'Deployment.json') -Raw | ConvertFrom-Json
        if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Install and configure SysAid for $($config.ServerUrl)")) { return }
        $msiPath = Join-Path $ScriptDir $config.MsiFile
        $transformPath = Join-Path $ScriptDir 'SysAidAgentx64.mst'
        if ((Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash -ne $config.MsiSha256 -or
            (Get-FileHash -LiteralPath $transformPath -Algorithm SHA256).Hash -ne $config.TransformSha256) { throw 'Bundled MSI or MST hash mismatch.' }
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as SYSTEM or elevated administrator.' }
        $logDir = 'C:\ProgramData\UMDLibraries\SysAid'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        & icacls.exe $logDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Unable to restrict the deployment log directory.' }
        Start-Transcript -Path (Join-Path $logDir 'Install-SysAidAgent.log') -Append -Force | Out-Null
        $transcribing = $true
        $agentKey = 'HKLM:\SOFTWARE\SysAid\InstalledProducts\SysAid'
        $markerKey = 'HKLM:\SOFTWARE\UMDLibraries\SysAidAgent'
        $current = if (Test-Path -LiteralPath $agentKey) { Get-ItemProperty -LiteralPath $agentKey } else { $null }
        if (Test-Path 'HKLM:\SOFTWARE\WOW6432Node\SysAid\InstalledProducts\SysAid') { throw 'An x86 agent exists. Pilot an explicit migration before deploying x64.' }
        if ($current -and ($current.ServerURL.TrimEnd('/') -ine $config.ServerUrl.TrimEnd('/') -or $current.AccountID -cne $config.AccountId)) {
            throw 'Existing agent belongs to a different server/account. Review its migration manually.'
        }
        $service = Get-Service -Name 'SysAidAgent' -ErrorAction SilentlyContinue
        if ($service -and -not $current) { throw 'An existing service lacks the expected MSI configuration. Review the previous installation.' }
        $installedVersion = if ($current) { [version]$current.DisplayVersion } else { [version]'0.0' }
        $msiResult = 0
        $needsRepair = $current -and $installedVersion -eq [version]$config.MinimumVersion -and
            (-not $service -or -not (Test-Path -LiteralPath (Join-Path $current.InstallLocation 'SysAidAgent.exe') -PathType Leaf))
        if ($installedVersion -lt [version]$config.MinimumVersion -or $needsRepair) {
            # Enrollment data stays in the transform, outside the process command line.
            $msiLog = Join-Path $logDir ('MSI-Install-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
            $arguments = "/i `"$msiPath`" TRANSFORMS=`"$transformPath`" /qn /norestart REBOOT=ReallySuppress /L* `"$msiLog`""
            if ($needsRepair) { $arguments += ' REINSTALL=ALL REINSTALLMODE=vomus' }
            $installation = Start-Process -FilePath "$env:WINDIR\System32\msiexec.exe" -ArgumentList $arguments -Wait -PassThru
            $msiResult = $installation.ExitCode
            Write-Output "Windows Installer exit code: $msiResult"
            if ($msiResult -eq 1618) { $result = 1618; return }
            if ($msiResult -notin @(0, 3010)) { throw "MSI installation failed with exit code $msiResult. Review the protected MSI log." }
        } else { Write-Output 'Baseline version or newer is installed; checking configuration and service.' }
        $installed = Get-ItemProperty -LiteralPath $agentKey
        if ([version]$installed.DisplayVersion -lt [version]$config.MinimumVersion -or
            $installed.ServerURL.TrimEnd('/') -ine $config.ServerUrl.TrimEnd('/') -or $installed.AccountID -cne $config.AccountId) {
            throw 'Post-install version or enrollment configuration verification failed.'
        }
        $executable = Join-Path $installed.InstallLocation 'SysAidAgent.exe'
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'SysAidAgent.exe is missing.' }
        Set-Service -Name 'SysAidAgent' -StartupType Automatic
        try {
            Start-Service -Name 'SysAidAgent'
            (Get-Service -Name 'SysAidAgent').WaitForStatus('Running', [timespan]::FromSeconds(30))
        } catch {
            if ($msiResult -ne 3010) { throw }
            Write-Warning 'The MSI requires a reboot. Verify the service and server check-in after restarting.'
        }
        # The marker is written last; detection also checks actual agent files, version, and enrollment.
        if (-not (Test-Path -LiteralPath $markerKey)) { New-Item -Path $markerKey -Force | Out-Null }
        Set-ItemProperty -Path $markerKey -Name ServerUrl -Value $config.ServerUrl -Force
        Set-ItemProperty -Path $markerKey -Name AccountId -Value $config.AccountId -Force
        Set-ItemProperty -Path $markerKey -Name PackageRevision -Value ([int]$config.PackageRevision) -Force
        Set-ItemProperty -Path $markerKey -Name InstalledAt -Value ((Get-Date).ToString('o')) -Force
        Write-Output 'SysAid installation and local configuration verified. Confirm check-in in the SysAid console.'
        $result = $msiResult
    } catch { Write-Error $_ -ErrorAction Continue; $result = 1 }
    finally {
        if ($transcribing) { Stop-Transcript | Out-Null }
        # A return inside the try (MSI busy) must still propagate its retry code to Intune.
        if (-not $WhatIfPreference) { exit $result }
    }
}
