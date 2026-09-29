<#
.SYNOPSIS
    Silently uninstalls the EPSON Advanced Printer Driver 5 for the TM-T20II.

.DESCRIPTION
    Intune Win32 uninstall script (runs as SYSTEM, non-interactive).

      1. Runs the bundled APD package with /s /uninstall /rN (documented silent uninstall, no reboot) (falls back to the registered
         UninstallString if the package isn't present).
      2. Removes any leftover TM-T20II queues and the printer driver.
      3. Deletes the EA5INSTMT20II driver package from the driver store.
      4. Removes the Intune detection sentinel.

    Exit codes: 0 = success, 1 = failure.

.PARAMETER InstallerName
    File name (or wildcard) of the Epson APD package bundled in the .intunewin.

.PARAMETER TimeoutSeconds
    Maximum seconds to wait for the Epson uninstaller.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-EpsonTMT20II.ps1

.NOTES
    Author:  Oji
    Date:    2026-09-28
    Version: 4.0.0
    Log:     C:\ProgramData\EpsonTMT20II\Uninstall.log
#>
[CmdletBinding()]
param(
    [string]$InstallerName = 'APD_5*_T20II.exe',
    [int]$TimeoutSeconds = 600
)

begin {
    $ErrorActionPreference = 'Stop'

    # Relaunch 64-bit, keeping CWD (the unpacked .intunewin content for the upload/paste method).
    $is32on64 = [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess
    if ($is32on64 -and $PSCommandPath) {
        $ps64 = Join-Path $env:WINDIR 'sysnative\WindowsPowerShell\v1.0\powershell.exe'
        $relaunchArgs = '-ExecutionPolicy Bypass -NoProfile -File "{0}" -InstallerName "{1}" -TimeoutSeconds {2}' -f $PSCommandPath, $InstallerName, $TimeoutSeconds
        $child = Start-Process -FilePath $ps64 -ArgumentList $relaunchArgs -WorkingDirectory (Get-Location).Path -NoNewWindow -Wait -PassThru
        exit $child.ExitCode
    }

    $SearchDirs = @($PSScriptRoot, (Get-Location).Path, [Environment]::CurrentDirectory) |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    $SysDir      = if ($is32on64) { Join-Path $env:WINDIR 'sysnative' } else { Join-Path $env:WINDIR 'System32' }
    $DriverName  = 'EPSON TM-T20II Receipt5'
    $DriverInf   = 'EA5INSTMT20II.INF'
    $SentinelKey = 'HKLM:\SOFTWARE\UMDLibraries\Intune\EpsonTMT20II-APD'
    $LogDir      = 'C:\ProgramData\EpsonTMT20II'
    $UninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    Start-Transcript -Path (Join-Path $LogDir 'Uninstall.log') -Append | Out-Null

    function Write-Log {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Message,
            [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
        )
        Write-Host ('[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
    }

    function Get-ApdUninstallEntry {
        [CmdletBinding()]
        param()
        foreach ($root in $UninstallRoots) {
            Get-ChildItem -Path $root -ErrorAction SilentlyContinue |
                Get-ItemProperty -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like 'EPSON Advanced Printer Driver*TM-T20II*' -and $_.UninstallString }
        }
    }
}

end {
    $exitCode = 0
    try {
        Write-Log '=== Epson TM-T20II APD uninstall started ==='
        Write-Log "PSCommandPath: '$PSCommandPath' | CWD: '$((Get-Location).Path)' | 64-bit: $([Environment]::Is64BitProcess)"

        # --- 1. Epson silent uninstall ---------------------------------------------
        $installer = foreach ($dir in $SearchDirs) {
            Get-ChildItem -Path $dir -Filter $InstallerName -File -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 1
        }
        $installer = $installer | Select-Object -First 1

        $filePath = $null
        $arguments = $null
        if ($installer) {
            $filePath  = $installer.FullName
            $arguments = '/s /uninstall /rN'
        }
        else {
            $entry = Get-ApdUninstallEntry | Select-Object -First 1
            if ($entry -and $entry.UninstallString -match '^\s*"([^"]+)"\s*(.*)$') {
                $filePath  = $Matches[1]
                $arguments = ('/s ' + $Matches[2]).Trim()
                if ($arguments -notmatch '/uninstall') { $arguments += ' /uninstall' }
                if ($arguments -notmatch '/r[YN]') { $arguments += ' /rN' }
            }
        }

        if ($filePath) {
            Write-Log "Running: `"$filePath`" $arguments"
            $proc = Start-Process -FilePath $filePath -ArgumentList $arguments -WindowStyle Hidden -PassThru
            if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
                throw "Epson uninstaller did not finish within $TimeoutSeconds seconds"
            }
            Write-Log "Epson uninstaller exit code: $($proc.ExitCode)"

            $deadline = (Get-Date).AddSeconds(120)
            while ((Get-ApdUninstallEntry) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
        }
        else {
            Write-Log 'No APD package or uninstall entry found - cleaning up manually' -Level WARN
        }

        # --- 2. Leftover queues and driver ------------------------------------------
        Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.DriverName -eq $DriverName } | ForEach-Object {
            try {
                Remove-Printer -Name $_.Name -Confirm:$false
                Write-Log "Removed queue '$($_.Name)' on '$($_.PortName)'"
            }
            catch { Write-Log "Could not remove queue '$($_.Name)': $_" -Level WARN }
        }

        if (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) {
            try {
                Remove-PrinterDriver -Name $DriverName -Confirm:$false
                Write-Log "Removed printer driver '$DriverName'"
            }
            catch { Write-Log "Could not remove printer driver: $_" -Level WARN }
        }

        # --- 3. Driver store --------------------------------------------------------
        $pnputil = Join-Path $SysDir 'pnputil.exe'
        $published = $null
        foreach ($line in (& $pnputil /enum-drivers)) {
            if ($line -match '^\s*Published Name:\s*(oem\d+\.inf)') { $published = $Matches[1] }
            elseif ($line -match '^\s*Original Name:\s*(.+?)\s*$' -and $Matches[1] -ieq $DriverInf -and $published) {
                Write-Log "Deleting driver package $published ($DriverInf)"
                & $pnputil /delete-driver $published /uninstall /force | ForEach-Object { Write-Log "pnputil: $_" }
            }
        }

        # --- 4. Sentinel ------------------------------------------------------------
        if (Test-Path $SentinelKey) {
            Remove-Item -Path $SentinelKey -Recurse -Force
            Write-Log "Removed sentinel $SentinelKey"
        }

        Write-Log '=== Uninstall completed ==='
    }
    catch {
        Write-Log "Uninstall failed: $_" -Level ERROR
        $exitCode = 1
    }
    finally {
        Stop-Transcript | Out-Null
    }
    exit $exitCode
}
