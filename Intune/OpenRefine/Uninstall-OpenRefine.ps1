<#
.SYNOPSIS
Silently removes machine-wide OpenRefine installations without deleting user projects.
.NOTES
Author: UMD Libraries IT
Date: 2026-11-17
Version: 1.0.0
Run as SYSTEM or administrator. Also supports Intune's pasted script installer.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()
begin { $ErrorActionPreference = 'Stop' }
process {
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $logDirectory = 'C:\ProgramData\UMDLibraries\OpenRefine'
    $transcribing = $false
    $exitCode = 1
    try {
        . (Join-Path $ScriptDir 'OpenRefine.Common.ps1')
        if (-not $PSCmdlet.ShouldProcess('Machine-wide OpenRefine', 'Uninstall')) { return }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator or SYSTEM context required.' }
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        Start-Transcript -Path (Join-Path $logDirectory 'Uninstall-OpenRefine.log') -Append | Out-Null
        $transcribing = $true
        $installations = @(Get-OpenRefineInstallation)
        $processes = @(Get-CimInstance Win32_Process -Filter "Name='openrefine.exe' OR Name='java.exe' OR Name='javaw.exe'")
        foreach ($item in $installations) {
            $prefix = $item.Directory + '\'
            $busy = @($processes | Where-Object {
                ($_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) -or
                ($_.CommandLine -and $_.CommandLine.IndexOf($prefix, [StringComparison]::OrdinalIgnoreCase) -ge 0)
            })
            if ($busy.Count) { throw 'OpenRefine is running. Close it and retry to protect unsaved projects.' }
            if (-not $item.Uninstaller -or -not (Test-Path -LiteralPath $item.Uninstaller -PathType Leaf)) {
                throw "Registered uninstaller is missing for $($item.Directory)."
            }
            # Run the registered executable directly; never evaluate the registry command as code.
            $parent = [IO.Path]::GetFullPath((Split-Path -Parent $item.Uninstaller)).TrimEnd('\')
            if ($parent -ne $item.Directory -or (Split-Path -Leaf $item.Uninstaller) -notmatch '^unins\d+\.exe$') {
                throw 'The registered uninstaller path is unexpected.'
            }
            $nativeLog = Join-Path $logDirectory "OpenRefine-Uninstall-$($item.RegistryView).log"
            $arguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG="' + $nativeLog + '"'
            $result = Start-Process -FilePath $item.Uninstaller -ArgumentList $arguments -Wait -PassThru
            Write-Output "Uninstaller exit code: $($result.ExitCode)"
            if ($result.ExitCode -ne 0) { throw "Uninstaller failed with exit code $($result.ExitCode)." }
        }
        if (@(Get-OpenRefineInstallation).Count) { throw 'OpenRefine is still registered after uninstall.' }
        Write-Output 'Machine-wide OpenRefine is absent. User profile projects were not explicitly removed.'
        $exitCode = 0
    }
    catch { Write-Output "ERROR: $($_.Exception.Message)"; $exitCode = 1 }
    finally { if ($transcribing) { Stop-Transcript | Out-Null } }
    exit $exitCode
}
