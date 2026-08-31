<#
.SYNOPSIS
    Silently installs Pharos Remote for deployment through Microsoft Intune.

.DESCRIPTION
    Validates the bundled Pharos Remote installer, configures the 32-bit Pharos
    Database Server registry values, runs the installer silently, validates the
    installed files, copies the Pharos Remote shortcut to the Public Desktop,
    and writes an Intune detection sentinel only after success.

.PARAMETER DatabaseServer
    FQDN of the server running the Pharos Database Service (not the SQL server).

.PARAMETER Port
    TCP port used by the Pharos Database Service.

.PARAMETER TimeoutSeconds
    Pharos Database Service connection timeout written to the registry.

.NOTES
    Author: Oji / University of Maryland Libraries
    Date: 2026-08-26
    Version: 1.1.0
    Runs non-interactively as SYSTEM under the Intune Management Extension.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DatabaseServer = 'LIBRDB407DV.ad.umd.edu',

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$Port = 2355,

    [Parameter()]
    [ValidateRange(1, 86400)]
    [int]$TimeoutSeconds = 120
)

begin {
    $ErrorActionPreference = 'Stop'
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $installerPath = Join-Path -Path $scriptDir -ChildPath 'RemoteInstaller.exe'
    $expectedInstallerSha256 = 'DCC4D481CA0135DB23C27F3E78D4CE67B3052F0FE35621CF08AE3D5D0769A656'
    $packageVersion = '9.2.10000.194'
    $logDirectory = Join-Path -Path $env:ProgramData -ChildPath 'PharosRemote'
    $logPath = Join-Path -Path $logDirectory -ChildPath 'InstallPharosRemote.log'
    $commonStartMenu = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonStartMenu)
    $startMenuShortcut = Join-Path -Path $commonStartMenu -ChildPath 'Programs\Pharos\Pharos Remote.lnk'
    $publicDesktopDirectory = Join-Path -Path $env:PUBLIC -ChildPath 'Desktop'
    $publicDesktopShortcut = Join-Path -Path $publicDesktopDirectory -ChildPath 'Pharos Remote.lnk'
    $transcriptStarted = $false
    $finalExitCode = 0
}

process {
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Install Pharos Remote $packageVersion")) {
        return
    }

    try {
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }
        Start-Transcript -Path $logPath -Append | Out-Null
        $transcriptStarted = $true

        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
        if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Administrative rights are required. Configure the Intune app to install in System context.'
        }

        if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
            throw "Bundled installer not found: $installerPath"
        }

        $actualInstallerSha256 = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
        if ($actualInstallerSha256 -ne $expectedInstallerSha256) {
            throw "RemoteInstaller.exe SHA-256 mismatch. Expected $expectedInstallerSha256; found $actualInstallerSha256."
        }

        $dotNetRelease = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction SilentlyContinue).Release
        if (-not $dotNetRelease -or $dotNetRelease -lt 393295) {
            throw 'Microsoft .NET Framework 4.6 or later is required by Pharos Remote.'
        }

        $tcpClient = [Net.Sockets.TcpClient]::new()
        try {
            $connectTask = $tcpClient.ConnectAsync($DatabaseServer, $Port)
            if (-not $connectTask.Wait(5000) -or -not $tcpClient.Connected) {
                Write-Warning "TCP connectivity to $DatabaseServer`:$Port was not confirmed. The installer will still be allowed to determine connectivity."
            }
        }
        catch {
            Write-Warning "TCP connectivity to $DatabaseServer`:$Port was not confirmed: $($_.Exception.Message)"
        }
        finally {
            $tcpClient.Dispose()
        }

        # A 32-bit PowerShell process is already redirected to the 32-bit registry
        # view. A 64-bit process must explicitly address WOW6432Node.
        $databaseRegPath = if ([Environment]::Is64BitOperatingSystem -and [Environment]::Is64BitProcess) {
            'HKLM:\SOFTWARE\WOW6432Node\Pharos\Database Server'
        }
        else {
            'HKLM:\SOFTWARE\Pharos\Database Server'
        }

        if (-not (Test-Path -LiteralPath $databaseRegPath)) {
            New-Item -Path $databaseRegPath -Force | Out-Null
        }
        Set-ItemProperty -LiteralPath $databaseRegPath -Name 'Host Address' -Value $DatabaseServer -Type String -Force
        Set-ItemProperty -LiteralPath $databaseRegPath -Name 'Port Name' -Value ([string]$Port) -Type String -Force
        Set-ItemProperty -LiteralPath $databaseRegPath -Name 'Timeout' -Value $TimeoutSeconds -Type DWord -Force

        Write-Output "Starting Pharos Remote $packageVersion silent installation."
        $installerProcess = Start-Process -FilePath $installerPath -ArgumentList '/q' -WorkingDirectory $scriptDir -PassThru
        if (-not $installerProcess.WaitForExit(1800000)) {
            $installerProcess.Kill()
            throw 'RemoteInstaller.exe exceeded the 30-minute installation timeout and was terminated.'
        }

        $installerExitCode = $installerProcess.ExitCode
        if ($installerExitCode -notin 0, 1641, 3010) {
            throw "RemoteInstaller.exe returned unexpected exit code $installerExitCode."
        }

        $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
        $pharosBinCandidates = @(
            if ($programFilesX86) { Join-Path -Path $programFilesX86 -ChildPath 'Pharos\Bin' }
            Join-Path -Path $env:ProgramFiles -ChildPath 'Pharos\Bin'
        ) | Select-Object -Unique

        $installedBinPath = $pharosBinCandidates | Where-Object {
            (Test-Path -LiteralPath (Join-Path -Path $_ -ChildPath 'AdminLauncher.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path -Path $_ -ChildPath 'Uninst.exe') -PathType Leaf)
        } | Select-Object -First 1

        if (-not $installedBinPath) {
            throw 'The installer returned success, but AdminLauncher.exe and Uninst.exe were not found in a default Pharos\Bin directory.'
        }

        if (-not (Test-Path -LiteralPath $startMenuShortcut -PathType Leaf)) {
            throw "The installer returned success, but the expected Start Menu shortcut was not found: $startMenuShortcut"
        }
        if (-not (Test-Path -LiteralPath $publicDesktopDirectory)) {
            New-Item -Path $publicDesktopDirectory -ItemType Directory -Force | Out-Null
        }
        Copy-Item -LiteralPath $startMenuShortcut -Destination $publicDesktopShortcut -Force
        if (-not (Test-Path -LiteralPath $publicDesktopShortcut -PathType Leaf)) {
            throw "Failed to create the Public Desktop shortcut: $publicDesktopShortcut"
        }

        $sentinelRegPath = 'HKLM:\SOFTWARE\UMD Libraries\Intune\Pharos Remote'
        if (-not (Test-Path -LiteralPath $sentinelRegPath)) {
            New-Item -Path $sentinelRegPath -Force | Out-Null
        }
        Set-ItemProperty -LiteralPath $sentinelRegPath -Name 'PackageVersion' -Value $packageVersion -Type String -Force
        Set-ItemProperty -LiteralPath $sentinelRegPath -Name 'InstallerSha256' -Value $actualInstallerSha256 -Type String -Force
        Set-ItemProperty -LiteralPath $sentinelRegPath -Name 'DatabaseServer' -Value $DatabaseServer -Type String -Force
        Set-ItemProperty -LiteralPath $sentinelRegPath -Name 'PortName' -Value ([string]$Port) -Type String -Force
        Set-ItemProperty -LiteralPath $sentinelRegPath -Name 'Timeout' -Value $TimeoutSeconds -Type DWord -Force
        Set-ItemProperty -LiteralPath $sentinelRegPath -Name 'InstallDateUtc' -Value ([DateTime]::UtcNow.ToString('o')) -Type String -Force
        Set-ItemProperty -LiteralPath $sentinelRegPath -Name 'InstallPath' -Value $installedBinPath -Type String -Force
        Set-ItemProperty -LiteralPath $sentinelRegPath -Name 'DesktopShortcutPath' -Value $publicDesktopShortcut -Type String -Force

        Write-Output "Pharos Remote $packageVersion installed successfully to $installedBinPath with Public Desktop shortcut $publicDesktopShortcut."
        $finalExitCode = $installerExitCode
    }
    catch {
        Write-Error -Message "Pharos Remote installation failed: $($_.Exception.Message)" -ErrorAction Continue
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
