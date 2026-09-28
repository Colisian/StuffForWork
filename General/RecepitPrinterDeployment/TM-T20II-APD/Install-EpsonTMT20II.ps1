<#
.SYNOPSIS
    Silently installs the EPSON Advanced Printer Driver 5 (APD5) for the TM-T20II receipt printer.

.DESCRIPTION
    Intune Win32 install script (runs as SYSTEM, non-interactive).

    Replaces the v2 "driver-only" package. Staging the INF alone lets Windows bind the
    printer to a plain USB001 port, which is unreliable. APD5 additionally installs the
    EPSON Port Communication Service (PCS / "EPSON Port Handler Monitor") and enables
    Epson's PnP install, so when the TM-T20II is plugged in the queue is created on an
    ESDPRT### port ("USB TM-T20II") - the same result as a manual install.

    Steps:
      1. Remove legacy queues using the TM-T20II driver on non-ESDPRT ports, and unused
         Local Monitor USB### ports created by the v1 scripts.
      2. Run the bundled APD installer with /s (silent).
      3. Verify the driver and the EPSON Port Handler Monitor are registered.
      4. If a TM-T20II is already connected and no ESDPRT queue exists, re-enumerate the
         device so Epson's co-installer creates the queue (best effort).
      5. Write a registry sentinel for Intune detection.

    Works unchanged with either Intune Win32 install method:
      A) Command line: powershell.exe -File .\Install-EpsonTMT20II.ps1
      B) Installer type "PowerShell script": upload this .ps1 as the install script.
         Intune stores the script outside the package, so bundled files are found by
         searching $PSScriptRoot AND the current directory (the unpacked content).

    Exit codes: 0 = success, 1 = failure.

.PARAMETER InstallerName
    File name (or wildcard) of the Epson APD package bundled in the .intunewin.

.PARAMETER TimeoutSeconds
    Maximum seconds to wait for the installer and for driver/monitor registration.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-EpsonTMT20II.ps1

.NOTES
    Author:  Oji
    Date:    2026-09-28
    Version: 3.1.0
    Log:     C:\ProgramData\EpsonTMT20II\Install.log
#>
[CmdletBinding()]
param(
    [string]$InstallerName = 'APD_5*_T20II.exe',
    [int]$TimeoutSeconds = 600
)

begin {
    $ErrorActionPreference = 'Stop'

    # Intune's management extension is 32-bit; printer/PnP cmdlets must run 64-bit.
    # Relaunch keeps the current directory: with the Intune "PowerShell script" upload method the
    # script file lives in an IME staging folder, but CWD is the unpacked .intunewin content.
    $is32on64 = [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess
    if ($is32on64 -and $PSCommandPath) {
        $ps64 = Join-Path $env:WINDIR 'sysnative\WindowsPowerShell\v1.0\powershell.exe'
        $relaunchArgs = '-ExecutionPolicy Bypass -NoProfile -File "{0}" -InstallerName "{1}" -TimeoutSeconds {2}' -f $PSCommandPath, $InstallerName, $TimeoutSeconds
        $child = Start-Process -FilePath $ps64 -ArgumentList $relaunchArgs -WorkingDirectory (Get-Location).Path -NoNewWindow -Wait -PassThru
        exit $child.ExitCode
    }

    # Where to look for bundled files: script folder (command-line method) and CWD (upload/paste method).
    $SearchDirs = @($PSScriptRoot, (Get-Location).Path, [Environment]::CurrentDirectory) |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    $SysDir        = if ($is32on64) { Join-Path $env:WINDIR 'sysnative' } else { Join-Path $env:WINDIR 'System32' }
    $DriverName    = 'EPSON TM-T20II Receipt5'
    $MonitorKey    = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\EPSON Port Handler Monitor'
    $SentinelKey   = 'HKLM:\SOFTWARE\UMDLibraries\Intune\EpsonTMT20II-APD'
    $PackageVer    = '5.13.0.0'
    $LogDir        = 'C:\ProgramData\EpsonTMT20II'
    $DeviceFilter  = 'USBPRINT\EPSONTM-T20II*'

    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    Start-Transcript -Path (Join-Path $LogDir 'Install.log') -Append | Out-Null

    function Write-Log {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Message,
            [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
        )
        Write-Host ('[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
    }

    function Test-ApdReady {
        [CmdletBinding()]
        param()
        $driver = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
        return ([bool]$driver -and (Test-Path $MonitorKey))
    }

    function Get-EsdPrinter {
        [CmdletBinding()]
        param()
        Get-Printer -ErrorAction SilentlyContinue |
            Where-Object { $_.DriverName -eq $DriverName -and $_.PortName -like 'ESDPRT*' }
    }
}

end {
    $exitCode = 0
    try {
        Write-Log "=== Epson TM-T20II APD install v$PackageVer started ==="
        Write-Log "PSCommandPath: '$PSCommandPath' | CWD: '$((Get-Location).Path)' | 64-bit: $([Environment]::Is64BitProcess)"
        if ($is32on64) { Write-Log 'Running as 32-bit without a script path (pasted?) - using sysnative tools' -Level WARN }

        # --- 1. Locate the installer -------------------------------------------------
        $installer = foreach ($dir in $SearchDirs) {
            Get-ChildItem -Path $dir -Filter $InstallerName -File -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 1
        }
        $installer = $installer | Select-Object -First 1
        if (-not $installer) {
            throw "Installer '$InstallerName' not found in: $($SearchDirs -join '; ')"
        }
        $PackageDir = $installer.DirectoryName
        Write-Log "Installer: $($installer.FullName)"

        # --- 2. Clean up legacy (v1/v2) queues and ports ----------------------------
        $legacy = Get-Printer -ErrorAction SilentlyContinue |
            Where-Object { $_.DriverName -eq $DriverName -and $_.PortName -notlike 'ESDPRT*' }
        foreach ($p in $legacy) {
            try {
                Remove-Printer -Name $p.Name -Confirm:$false
                Write-Log "Removed legacy queue '$($p.Name)' on port '$($p.PortName)'"
            }
            catch { Write-Log "Could not remove legacy queue '$($p.Name)': $_" -Level WARN }
        }

        $inUse = @(Get-Printer -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PortName)
        $stalePorts = Get-PrinterPort -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^USB\d{3}$' -and $_.PortMonitor -eq 'Local Monitor' -and $inUse -notcontains $_.Name }
        foreach ($port in $stalePorts) {
            try {
                Remove-PrinterPort -Name $port.Name -Confirm:$false
                Write-Log "Removed stale Local Monitor port '$($port.Name)'"
            }
            catch { Write-Log "Could not remove stale port '$($port.Name)': $_" -Level WARN }
        }

        # --- 3. Silent APD install ---------------------------------------------------
        Write-Log "Running: `"$($installer.FullName)`" /s"
        $proc = Start-Process -FilePath $installer.FullName -ArgumentList '/s' -WorkingDirectory $PackageDir `
            -WindowStyle Hidden -PassThru
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            throw "Installer did not finish within $TimeoutSeconds seconds"
        }
        Write-Log "Installer exit code: $($proc.ExitCode)"

        # The wrapper can return before its child Setup.exe/msiexec finish - poll for the end state.
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while (-not (Test-ApdReady) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }

        if (-not (Test-ApdReady)) {
            throw "Post-install check failed: driver '$DriverName' present=$([bool](Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue)); monitor key present=$(Test-Path $MonitorKey)"
        }
        Write-Log "Driver '$DriverName' and EPSON Port Handler Monitor are registered"
        if ($proc.ExitCode -ne 0) {
            Write-Log "Installer returned $($proc.ExitCode) but end state is correct - treating as success" -Level WARN
        }

        # --- 4. Printer already plugged in? Make sure it lands on ESDPRT --------------
        $device = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -like $DeviceFilter } | Select-Object -First 1
        if ($device) {
            Write-Log "Connected device found: $($device.InstanceId)"
            $deadline = (Get-Date).AddSeconds(30)
            while (-not (Get-EsdPrinter) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }

            if (-not (Get-EsdPrinter)) {
                Write-Log 'No ESDPRT queue yet - re-enumerating the USB device'
                $pnputil = Join-Path $SysDir 'pnputil.exe'
                & $pnputil /remove-device "$($device.InstanceId)" | ForEach-Object { Write-Log "pnputil: $_" }
                Start-Sleep -Seconds 3
                & $pnputil /scan-devices | ForEach-Object { Write-Log "pnputil: $_" }

                $deadline = (Get-Date).AddSeconds(60)
                while (-not (Get-EsdPrinter) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
            }

            $esd = Get-EsdPrinter
            if ($esd) {
                $esd | ForEach-Object { Write-Log "Printer ready: '$($_.Name)' on '$($_.PortName)'" }
            }
            else {
                Write-Log 'Printer is connected but no ESDPRT queue was created. Unplug/replug the USB cable or reboot.' -Level WARN
            }
        }
        else {
            Write-Log 'No TM-T20II connected. The queue is created on ESDPRT### when the printer is plugged in.'
        }

        # --- 5. Detection sentinel -------------------------------------------------
        if (-not (Test-Path $SentinelKey)) { New-Item -Path $SentinelKey -Force | Out-Null }
        Set-ItemProperty -Path $SentinelKey -Name 'Version'     -Value $PackageVer -Force
        Set-ItemProperty -Path $SentinelKey -Name 'InstallDate' -Value (Get-Date -Format 's') -Force
        Set-ItemProperty -Path $SentinelKey -Name 'Installer'   -Value $installer.Name -Force
        Write-Log "Sentinel written: $SentinelKey (Version=$PackageVer)"

        Write-Log '=== Install completed successfully ==='
    }
    catch {
        Write-Log "Install failed: $_" -Level ERROR
        $exitCode = 1
    }
    finally {
        Stop-Transcript | Out-Null
    }
    exit $exitCode
}
