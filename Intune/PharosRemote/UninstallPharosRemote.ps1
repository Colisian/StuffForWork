<#
.SYNOPSIS
    Silently removes the Pharos Remote component deployed through Intune.

.DESCRIPTION
    Locates the Pharos uninstaller, requests silent removal of the Remote
    component, and removes only the UMD Intune detection sentinel. Shared Pharos
    Database Server settings are preserved because other Pharos components may
    use them.

.PARAMETER ComponentName
    Component token passed to the Pharos uninstaller.

.NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-26
    Version: 1.0.0
    Validate the vendor component token on a pilot device before production use.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ComponentName = 'Remote'
)

begin {
    $ErrorActionPreference = 'Stop'
    $logDirectory = Join-Path -Path $env:ProgramData -ChildPath 'PharosRemote'
    $logPath = Join-Path -Path $logDirectory -ChildPath 'UninstallPharosRemote.log'
    $transcriptStarted = $false
    $finalExitCode = 0
}

process {
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Uninstall Pharos component '$ComponentName'")) {
        return
    }

    try {
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }
        Start-Transcript -Path $logPath -Append | Out-Null
        $transcriptStarted = $true

        $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
        $uninstallerCandidates = @(
            if ($programFilesX86) { Join-Path -Path $programFilesX86 -ChildPath 'Pharos\Bin\Uninst.exe' }
            Join-Path -Path $env:ProgramFiles -ChildPath 'Pharos\Bin\Uninst.exe'
        ) | Select-Object -Unique
        $uninstallerPath = $uninstallerCandidates | Where-Object {
            Test-Path -LiteralPath $_ -PathType Leaf
        } | Select-Object -First 1

        if ($uninstallerPath) {
            Write-Output "Starting silent removal with $uninstallerPath /s $ComponentName"
            $uninstallerProcess = Start-Process -FilePath $uninstallerPath -ArgumentList @('/s', $ComponentName) -PassThru
            if (-not $uninstallerProcess.WaitForExit(1800000)) {
                $uninstallerProcess.Kill()
                throw 'Uninst.exe exceeded the 30-minute uninstall timeout and was terminated.'
            }

            $uninstallerExitCode = $uninstallerProcess.ExitCode
            if ($uninstallerExitCode -notin 0, 1641, 3010) {
                throw "Uninst.exe returned unexpected exit code $uninstallerExitCode."
            }
            $finalExitCode = $uninstallerExitCode
        }
        else {
            $adminLauncherCandidates = @(
                if ($programFilesX86) { Join-Path -Path $programFilesX86 -ChildPath 'Pharos\Bin\AdminLauncher.exe' }
                Join-Path -Path $env:ProgramFiles -ChildPath 'Pharos\Bin\AdminLauncher.exe'
            ) | Select-Object -Unique
            $adminLauncherExists = $adminLauncherCandidates | Where-Object {
                Test-Path -LiteralPath $_ -PathType Leaf
            } | Select-Object -First 1

            if ($adminLauncherExists) {
                throw "Pharos AdminLauncher.exe exists at $adminLauncherExists, but Uninst.exe was not found."
            }
            Write-Warning 'Pharos program files were not found; treating the application as already removed.'
        }

        $sentinelPaths = @('HKLM:\SOFTWARE\UMD Libraries\Intune\Pharos Remote')
        if ([Environment]::Is64BitOperatingSystem -and [Environment]::Is64BitProcess) {
            $sentinelPaths += 'HKLM:\SOFTWARE\WOW6432Node\UMD Libraries\Intune\Pharos Remote'
        }

        foreach ($sentinelPath in $sentinelPaths | Select-Object -Unique) {
            if (Test-Path -LiteralPath $sentinelPath) {
                Remove-Item -LiteralPath $sentinelPath -Force
            }
        }

        Write-Output 'Pharos Remote uninstall command completed. Shared Pharos configuration was preserved.'
    }
    catch {
        Write-Error -Message "Pharos Remote uninstallation failed: $($_.Exception.Message)" -ErrorAction Continue
        $finalExitCode = 1
    }
    finally {
        if ($transcriptStarted) {
            Stop-Transcript | Out-Null
        }
    }
}

end {
    exit $finalExitCode
}
