<#
.SYNOPSIS
    Removes the Canon Generic Plus UFR II driver if no printer still uses it.

.DESCRIPTION
    Refuses (exit 1) while any printer is bound to the driver - uninstall the printer apps
    first. Otherwise removes the print driver, deletes its package from the driver store,
    and clears the detection sentinel.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-PrinterDriver.ps1

.NOTES
    Author:  Oji (cmcleod1@umd.edu)
    Date:    2026-09-22
    Version: 1.1.0
    Log:     C:\ProgramData\StaffPrinters\Driver-Uninstall.log
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DriverName = 'Canon Generic Plus UFR II'
)

begin {
    $ErrorActionPreference = 'Stop'

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess -and $PSCommandPath) {
        $ps64 = Join-Path $env:WINDIR 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
        $relaunchArgs = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', $PSCommandPath) + @('-DriverName', $DriverName)
        if ($WhatIfPreference) { $relaunchArgs += '-WhatIf' }
        & $ps64 @relaunchArgs
        exit $LASTEXITCODE
    }

    $pnputil = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { "$env:WINDIR\Sysnative\pnputil.exe" } else { "$env:WINDIR\System32\pnputil.exe" }

    $logDir = 'C:\ProgramData\StaffPrinters'
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force -WhatIf:$false | Out-Null }
    $sentinel = 'HKLM:\SOFTWARE\UMDLibraries\StaffPrinters\Driver'
}

end {
    $exitCode = 0
    $transcribing = $false
    try {
        try { Start-Transcript -Path (Join-Path $logDir 'Driver-Uninstall.log') -Append -WhatIf:$false | Out-Null; $transcribing = $true } catch { }

        $inUse = Get-Printer | Where-Object DriverName -EQ $DriverName
        if ($inUse) { throw "Driver still used by: $($inUse.Name -join ', '). Uninstall those printers first." }

        $driver = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
        if ($driver) {
            $infPath = $driver.InfPath
            if ($PSCmdlet.ShouldProcess($DriverName, 'Remove-PrinterDriver')) { Remove-PrinterDriver -Name $DriverName }

            # Map the DriverStore INF back to its oemNN.inf published name for pnputil
            $oem = Get-WindowsDriver -Online | Where-Object { $_.OriginalFileName -eq $infPath } |
                Select-Object -ExpandProperty Driver -First 1
            if ($oem -and $PSCmdlet.ShouldProcess($oem, 'pnputil /delete-driver')) {
                & $pnputil /delete-driver $oem /uninstall | Out-Null
                Write-Output "Deleted driver package $oem (pnputil exit $LASTEXITCODE)."
            }
        } else {
            Write-Output "Driver '$DriverName' not present."
        }

        if ((Test-Path $sentinel) -and $PSCmdlet.ShouldProcess($sentinel, 'Remove sentinel')) {
            Remove-Item -Path $sentinel -Force
        }
    } catch {
        Write-Error "Driver uninstall failed: $($_.Exception.Message)" -ErrorAction Continue
        $exitCode = 1
    } finally {
        if ($transcribing) { Stop-Transcript | Out-Null }
    }
    exit $exitCode
}
