<#
.SYNOPSIS
    Silently installs the Epson TM-T20II (APD 5.13) including its ESDPRT001 USB port and printer queue.

.DESCRIPTION
    Intune Win32 install script (runs as SYSTEM, non-interactive).

    Uses Epson's documented "Copy Installation" (APD5 Install Manual rev G, chapter 3):
        APD_513_T20II.exe /s /f1"<full path to script .inf>" /rN
    The script .inf is exported ONCE from a reference PC where the printer works
    (Register, Change and Delete EPSON TM Printer > Copy Installation > Create >
    "Copy data file only"). It contains the printer, the ESDPRT001 "USB TM-T20II" port and
    the driver settings, so every PC gets the same working configuration with no manual steps.

    Plain "/s" is NOT a valid APD option (Epson result 3 = "Specified command option cannot be used").

    Steps:
      1. If already installed (sentinel + queue on ESDPRT) -> exit 0.
      2. Remove anything that blocks copy installation: existing TM-T20II queues (result 4),
         an existing APD install (result -3), v2 driver-only leftovers.
      3. Run the copy installation silently, no reboot.
      4. Verify a queue exists on an ESDPRT port; write the detection sentinel.

    Works unchanged with either Intune Win32 install method:
      A) Command line: powershell.exe -File .\Install-EpsonTMT20II.ps1
      B) Installer type "PowerShell script": upload this .ps1 as the install script.
         Bundled files are found via $PSScriptRoot AND the current directory (unpacked content).

    Exit codes: 0 = success, 1 = failure.

.PARAMETER InstallerName
    File name (or wildcard) of the Epson APD package bundled in the .intunewin.

.PARAMETER CopyScriptName
    File name (or wildcard) of the Epson copy-installation script (.inf) bundled in the .intunewin.

.PARAMETER TimeoutSeconds
    Maximum seconds to wait for each Epson installer run.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-EpsonTMT20II.ps1

.NOTES
    Author:  Oji
    Date:    2026-09-28
    Version: 4.0.0
    Log:     C:\ProgramData\EpsonTMT20II\Install.log
#>
[CmdletBinding()]
param(
    [string]$InstallerName = 'APD_5*_T20II.exe',
    [string]$CopyScriptName = '*.inf',
    [int]$TimeoutSeconds = 600
)

begin {
    $ErrorActionPreference = 'Stop'

    # Intune's management extension is 32-bit; printer cmdlets must run 64-bit.
    # Relaunch keeps CWD, which is the unpacked .intunewin content for the upload method.
    $is32on64 = [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess
    if ($is32on64 -and $PSCommandPath) {
        $ps64 = Join-Path $env:WINDIR 'sysnative\WindowsPowerShell\v1.0\powershell.exe'
        $relaunchArgs = '-ExecutionPolicy Bypass -NoProfile -File "{0}" -InstallerName "{1}" -CopyScriptName "{2}" -TimeoutSeconds {3}' -f $PSCommandPath, $InstallerName, $CopyScriptName, $TimeoutSeconds
        $child = Start-Process -FilePath $ps64 -ArgumentList $relaunchArgs -WorkingDirectory (Get-Location).Path -NoNewWindow -Wait -PassThru
        exit $child.ExitCode
    }

    $SearchDirs = @($PSScriptRoot, (Get-Location).Path, [Environment]::CurrentDirectory) |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    $DriverName  = 'EPSON TM-T20II Receipt5'
    $MonitorKey  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\EPSON Port Handler Monitor'
    $SentinelKey = 'HKLM:\SOFTWARE\UMDLibraries\Intune\EpsonTMT20II-APD'
    $PackageVer  = '5.13.0.0'
    $LogDir      = 'C:\ProgramData\EpsonTMT20II'
    $EpsonLog    = Join-Path $env:ProgramData 'EPSON\EPSON Advanced Printer Driver 5\CopyInstallLog\CopyInstallLog.txt'

    # Epson "Install Result" codes (APD5 Install Manual rev G, p.46)
    $EpsonResults = @{
        0    = 'Installation completed correctly'
        1    = 'Administrator privilege required, or not enough disk space'
        2    = 'Specified script file was not found'
        3    = 'Specified command option cannot be used'
        4    = 'The printer is already installed - uninstall the printer first'
        5    = 'A newer version is already installed'
        6    = 'Script file and APD5 installer package do not match'
        7    = 'Script file OS bitness (32/64-bit) does not match this OS'
        8    = 'Script file cannot be used with this package version'
        9    = 'Script file cannot be used with this package'
        -3   = 'APD5 is already installed'
        -1   = 'Files in use / installation failed - close applications and retry'
        1151 = 'OS not supported by APD5'
        1223 = 'User cancelled the installation'
    }

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

    function Find-PackageFile {
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$Filter)
        foreach ($dir in $SearchDirs) {
            $hit = Get-ChildItem -Path $dir -Filter $Filter -File -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 1
            if ($hit) { return $hit }
        }
    }

    function Get-ApdUninstallEntry {
        [CmdletBinding()]
        param()
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
            ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
            Where-Object { $_.DisplayName -like 'EPSON Advanced Printer Driver*' } | Select-Object -First 1
    }

    function Get-EsdQueue {
        [CmdletBinding()]
        param()
        Get-Printer -ErrorAction SilentlyContinue |
            Where-Object { $_.DriverName -eq $DriverName -and $_.PortName -like 'ESDPRT*' }
    }

    function Invoke-Epson {
        # Runs the APD installer and returns its exit code (the documented "Install Result").
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$FilePath,
            [Parameter(Mandatory)][string]$Arguments
        )
        Write-Log "Running: `"$FilePath`" $Arguments"
        $proc = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory (Split-Path $FilePath) `
            -WindowStyle Hidden -PassThru
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            throw "Epson installer did not finish within $TimeoutSeconds seconds"
        }
        $code = $proc.ExitCode
        $text = if ($EpsonResults.ContainsKey($code)) { $EpsonResults[$code] } else { 'Unknown result' }
        Write-Log "Epson result: $code ($text)"
        return $code
    }

    function Write-EpsonLog {
        [CmdletBinding()]
        param()
        if (Test-Path $EpsonLog) {
            Write-Log "--- $EpsonLog (last 15 lines)"
            Get-Content $EpsonLog -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { Write-Log "  $_" }
        }
    }
}

end {
    $exitCode = 0
    try {
        Write-Log "=== Epson TM-T20II APD $PackageVer copy installation started ==="
        Write-Log "PSCommandPath: '$PSCommandPath' | CWD: '$((Get-Location).Path)' | 64-bit: $([Environment]::Is64BitProcess)"

        # --- 1. Already done? ---------------------------------------------------------
        $current = (Get-ItemProperty -Path $SentinelKey -Name Version -ErrorAction SilentlyContinue).Version
        $existing = Get-EsdQueue
        if ($current -eq $PackageVer -and $existing) {
            $existing | ForEach-Object { Write-Log "Already installed: '$($_.Name)' on $($_.PortName) - nothing to do" }
            exit 0
        }

        # --- 2. Locate bundled files -----------------------------------------------------
        $installer = Find-PackageFile -Filter $InstallerName
        if (-not $installer) { throw "Installer '$InstallerName' not found in: $($SearchDirs -join '; ')" }
        $copyScript = Find-PackageFile -Filter $CopyScriptName
        if (-not $copyScript) {
            throw "Epson copy-installation script '$CopyScriptName' not found in: $($SearchDirs -join '; '). Create it on a reference PC (see runbook) and rebuild the package."
        }
        Write-Log "Installer:   $($installer.FullName)"
        Write-Log "Copy script: $($copyScript.FullName)"

        # --- 3. Clear blockers (Epson results 4 and -3) ---------------------------------
        Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.DriverName -eq $DriverName } | ForEach-Object {
            Remove-Printer -Name $_.Name -Confirm:$false
            Write-Log "Removed existing queue '$($_.Name)' on '$($_.PortName)' (copy install requires no existing printer)"
        }

        $entry = Get-ApdUninstallEntry
        if ($entry) {
            Write-Log "Existing APD found: $($entry.DisplayName) $($entry.DisplayVersion) - removing before copy install"
            $code = Invoke-Epson -FilePath $installer.FullName -Arguments '/s /uninstall /rN'
            if ($code -ne 0) { Write-Log "Silent uninstall returned $code - continuing" -Level WARN }
            $deadline = (Get-Date).AddSeconds(120)
            while ((Get-ApdUninstallEntry) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
        }
        elseif (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) {
            # v2 package staged the driver without APD
            try {
                Remove-PrinterDriver -Name $DriverName -Confirm:$false
                Write-Log "Removed v2 driver-only install of '$DriverName'"
            }
            catch { Write-Log "Could not remove v2 driver (continuing): $_" -Level WARN }
        }

        # --- 4. Copy installation -------------------------------------------------------
        $code = Invoke-Epson -FilePath $installer.FullName -Arguments ('/s /f1"{0}" /rN' -f $copyScript.FullName)
        Write-EpsonLog
        if ($code -ne 0) { throw "Epson copy installation failed with result $code" }

        # --- 5. Verify ------------------------------------------------------------------
        $deadline = (Get-Date).AddSeconds(60)
        while (-not (Get-EsdQueue) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
        $queue = Get-EsdQueue
        if (-not $queue) {
            Get-Printer | Where-Object { $_.DriverName -eq $DriverName } |
                ForEach-Object { Write-Log "Queue found on non-ESDPRT port: '$($_.Name)' on '$($_.PortName)'" -Level WARN }
            throw 'Copy installation returned 0 but no TM-T20II queue exists on an ESDPRT port'
        }
        $queue | ForEach-Object { Write-Log "Printer ready: '$($_.Name)' on $($_.PortName)" }
        Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'ESDPRT*' } |
            ForEach-Object { Write-Log "Port: $($_.Name) | $($_.Description)" }
        Write-Log "Port monitor registered: $(Test-Path $MonitorKey)"

        # --- 6. Detection sentinel ------------------------------------------------------
        if (-not (Test-Path $SentinelKey)) { New-Item -Path $SentinelKey -Force | Out-Null }
        Set-ItemProperty -Path $SentinelKey -Name 'Version'     -Value $PackageVer -Force
        Set-ItemProperty -Path $SentinelKey -Name 'InstallDate' -Value (Get-Date -Format 's') -Force
        Set-ItemProperty -Path $SentinelKey -Name 'CopyScript'  -Value $copyScript.Name -Force
        Write-Log "Sentinel written: $SentinelKey (Version=$PackageVer)"

        Write-Log '=== Install completed successfully ==='
    }
    catch {
        Write-Log "Install failed: $_" -Level ERROR
        $exitCode = 1
    }
    finally {
        try { Stop-Transcript | Out-Null } catch { }
    }
    exit $exitCode
}
