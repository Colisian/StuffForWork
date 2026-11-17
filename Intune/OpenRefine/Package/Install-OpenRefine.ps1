<#
.SYNOPSIS
Installs OpenRefine silently for all users, using the bundled Java runtime.
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
        $config = Get-Content -LiteralPath (Join-Path $ScriptDir 'OpenRefine.config.json') -Raw | ConvertFrom-Json
        $installer = Join-Path $ScriptDir $config.InstallerFile
        $expectedVersion = [version]$config.Version
        if (-not $PSCmdlet.ShouldProcess("OpenRefine $expectedVersion", 'Install for all users')) { return }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator or SYSTEM context required.' }
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        Start-Transcript -Path (Join-Path $logDirectory 'Install-OpenRefine.log') -Append | Out-Null
        $transcribing = $true
        if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ne $config.SHA256) {
            throw 'Installer SHA-256 does not match the verified release.'
        }
        $installations = @(Get-OpenRefineInstallation)
        $existing = @($installations | Where-Object { $_.Version -ge $expectedVersion -and $_.Complete })
        if ($existing.Count) {
            Write-Output "OpenRefine $($existing[0].Version) is already installed."
            $exitCode = 0
        }
        else {
            # Avoid a downgrade even if a newer installation needs repair.
            if (@($installations | Where-Object { $_.Version -gt $expectedVersion }).Count) {
                throw 'A newer OpenRefine version is registered; repair it using its own installer.'
            }
            # Check only OpenRefine and Java processes associated with these install folders.
            $processes = @(Get-CimInstance Win32_Process -Filter "Name='openrefine.exe' OR Name='java.exe' OR Name='javaw.exe'")
            foreach ($item in $installations) {
                $prefix = $item.Directory + '\'
                $busy = @($processes | Where-Object {
                    ($_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) -or
                    ($_.CommandLine -and $_.CommandLine.IndexOf($prefix, [StringComparison]::OrdinalIgnoreCase) -ge 0)
                })
                if ($busy.Count) { throw 'OpenRefine is running. Close it and retry to protect unsaved projects.' }
            }
            $nativeLog = Join-Path $logDirectory 'OpenRefine-Setup.log'
            $arguments = '/VERYSILENT /SUPPRESSMSGBOXES /SP- /ALLUSERS /LANG=english /NORESTART ' +
                '/RESTARTEXITCODE=3010 /NOCLOSEAPPLICATIONS /NORESTARTAPPLICATIONS ' +
                '/MERGETASKS="!desktopicon" /LOG="' + $nativeLog + '"'
            $result = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru
            Write-Output "Installer exit code: $($result.ExitCode)"
            if ($result.ExitCode -notin @(0, 3010)) { throw "Installer failed with exit code $($result.ExitCode)." }
            $installed = @(Get-OpenRefineInstallation | Where-Object { $_.Version -ge $expectedVersion -and $_.Complete })
            if (-not $installed.Count) { throw 'Post-install verification failed: registration, application, Java, or server JAR missing.' }
            Write-Output "Verified OpenRefine $($installed[0].Version) at $($installed[0].Directory)."
            $exitCode = $result.ExitCode
        }
    }
    catch { Write-Output "ERROR: $($_.Exception.Message)"; $exitCode = 1 }
    finally { if ($transcribing) { Stop-Transcript | Out-Null } }
    exit $exitCode
}
