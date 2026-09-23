<#
.SYNOPSIS
    Removes a direct TCP/IP staff printer and its port.

.DESCRIPTION
    Reads the bundled printer.csv and removes ONLY that printer and its IP_<fqdn> port.
    The printer driver is intentionally left installed - it is shared by every staff
    printer and owned by the driver app.
    Works as a command-line uninstall or pasted into Intune's PowerShell script box.

    Exit codes: 0 success (including "already absent"), 1 failure.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-StaffPrinter.ps1

.NOTES
    Author:  Oji (cmcleod1@umd.edu)
    Date:    2026-09-22
    Version: 1.0.0
    Log:     C:\ProgramData\StaffPrinters\<PrinterName>-Uninstall.log
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$CsvPath
)

begin {
    $ErrorActionPreference = 'Stop'

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess -and $PSCommandPath) {
        $ps64 = Join-Path $env:WINDIR 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
        $relaunchArgs = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', $PSCommandPath)
        if ($CsvPath) { $relaunchArgs += @('-CsvPath', $CsvPath) }
        & $ps64 @relaunchArgs
        exit $LASTEXITCODE
    }

    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    if (-not $CsvPath) { $CsvPath = Join-Path $ScriptDir 'printer.csv' }

    $logDir = 'C:\ProgramData\StaffPrinters'
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force -WhatIf:$false | Out-Null }
}

process {
    $exitCode = 0
    $transcribing = $false
    try {
        $printer = Import-Csv -Path $CsvPath | Select-Object -First 1
        $name = $printer.Name.Trim()
        $port = "IP_$($printer.PortAddress.Trim())"

        try {
            Start-Transcript -Path (Join-Path $logDir "$name-Uninstall.log") -Append -WhatIf:$false | Out-Null
            $transcribing = $true
        } catch { }

        if (Get-Printer -Name $name -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess($name, 'Remove-Printer')) {
                Remove-Printer -Name $name
                Write-Output "Removed printer '$name'."
            }
        } else {
            Write-Output "Printer '$name' not present."
        }

        if (Get-PrinterPort -Name $port -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess($port, 'Remove-PrinterPort')) {
                # The spooler can hold the port briefly after the printer is deleted
                $removed = $false
                foreach ($attempt in 1..5) {
                    try { Remove-PrinterPort -Name $port; $removed = $true; break }
                    catch { Start-Sleep -Seconds 3 }
                }
                if (-not $removed) { throw "Port '$port' could not be removed (still in use?)." }
                Write-Output "Removed port '$port'."
            }
        } else {
            Write-Output "Port '$port' not present."
        }
    } catch {
        Write-Error "Uninstall failed: $($_.Exception.Message)" -ErrorAction Continue
        $exitCode = 1
    } finally {
        if ($transcribing) { Stop-Transcript | Out-Null }
    }
    exit $exitCode
}
