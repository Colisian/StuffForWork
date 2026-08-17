<#
.SYNOPSIS
    Silently removes ArcGIS Drone2Map 2026.1.

.DESCRIPTION
    Removes only the MSI ProductCode bundled with this Win32 app. This version-specific
    behavior avoids accidentally uninstalling a later Drone2Map release that may supersede
    this app in Intune. The script is idempotent and returns success when this build is
    already absent.

    The application registry sentinel is removed after Windows Installer reports success.
    User-created projects and per-user ArcGIS sign-in preferences are intentionally retained.

    Authored for dual-method Intune use:
      A) Command line: powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-ArcGISDrone2Map.ps1
      B) Pasted into the Intune Win32 "PowerShell script installer" box (no edits required).

.EXAMPLE
    .\Uninstall-ArcGISDrone2Map.ps1

.NOTES
    Author  : Oji McLeod (cmcleod1@umd.edu) - ITFO / Digital Services & Technologies, UMD Libraries
    Date    : 2026-08-17
    Version : 1.1.0
    Exit    : 0 = removed/already absent, 3010 = removed/reboot required, 1 = failure

    1.1.0 - Added a 64-bit host check for consistent MSI and sentinel registry access.
    1.0.0 - Initial release.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

begin {
    $ErrorActionPreference = 'Stop'

    $componentRoot = 'C:\ProgramData\ArcGISDrone2Map'
    if (-not (Test-Path -LiteralPath $componentRoot)) {
        New-Item -Path $componentRoot -ItemType Directory -Force | Out-Null
    }

    Start-Transcript -Path (Join-Path $componentRoot 'Uninstall-ArcGISDrone2Map.log') -Append | Out-Null

    $expectedProductCode = '{E4CA5C88-DD5C-4686-8070-CF6CAC6B6FDA}'
    $sentinelPath = 'HKLM:\SOFTWARE\UMD\Intune\ArcGISDrone2Map'
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
}

process {
    try {
        Write-Output "[$(Get-Date -Format s)] ArcGIS Drone2Map uninstall starting."

        if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
            throw 'This uninstaller must run in 64-bit PowerShell. In Intune, set Run script as 32-bit process on 64-bit clients to No.'
        }

        $registered = $false
        foreach ($root in $uninstallRoots) {
            if (Test-Path -LiteralPath (Join-Path $root $expectedProductCode)) {
                $registered = $true
                break
            }
        }

        if (-not $registered) {
            Write-Output "Product $expectedProductCode is not registered; treating the app as already removed."
            if ((Test-Path -LiteralPath $sentinelPath) -and
                $PSCmdlet.ShouldProcess($sentinelPath, 'Remove stale ArcGIS Drone2Map detection sentinel')) {
                Remove-Item -LiteralPath $sentinelPath -Recurse -Force
            }
            $script:result = 0
            return
        }

        if (-not $PSCmdlet.ShouldProcess($expectedProductCode, 'Uninstall ArcGIS Drone2Map 2026.1')) {
            Write-Output 'ShouldProcess declined; nothing was removed.'
            $script:result = 0
            return
        }

        $nativeLog = Join-Path $componentRoot 'Drone2Map-MSI-Uninstall.log'
        $msiArguments = @(
            '/x'
            $expectedProductCode
            '/qn'
            '/norestart'
            '/l*v'
            "`"$nativeLog`""
        )

        Write-Output "Running: msiexec.exe $($msiArguments -join ' ')"
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArguments -Wait -PassThru
        $exitCode = $process.ExitCode
        Write-Output "Windows Installer exit code: $exitCode"

        switch ($exitCode) {
            0     { $script:result = 0 }
            1605  { $script:result = 0 }
            3010  { $script:result = 3010 }
            1641  { $script:result = 3010 }
            default {
                throw "ArcGIS Drone2Map uninstall failed with exit code $exitCode. See '$nativeLog'."
            }
        }

        if (Test-Path -LiteralPath $sentinelPath) {
            Remove-Item -LiteralPath $sentinelPath -Recurse -Force
        }

        Write-Output 'ArcGIS Drone2Map uninstall completed. User projects and preferences were retained.'
    }
    catch {
        Write-Output "ERROR: $($_.Exception.Message)"
        Write-Output $_.ScriptStackTrace
        $script:result = 1
    }
}

end {
    if ($null -eq $script:result) { $script:result = 0 }
    Write-Output "[$(Get-Date -Format s)] Exiting with code $script:result"
    try { Stop-Transcript | Out-Null } catch { }
    exit $script:result
}
