<#
.SYNOPSIS
    Installs the Canon Generic Plus UFR II printer driver machine-wide.

.DESCRIPTION
    Stages every *.inf under the bundled .\Driver\ folder into the driver store with pnputil,
    then registers the print driver with Add-PrinterDriver. Deploy this as its own Win32 app
    and set it as a DEPENDENCY of each staff printer app, so the ~driver payload is uploaded
    once instead of 32 times and uninstalling one printer never touches the shared driver.
    Also writes a registry sentinel used by the detection rule.

    Exit codes: 0 success, 1 failure.

.PARAMETER DriverName
    Exact driver name from the INF [Models] section. Default: 'Canon Generic Plus UFR II'.

.PARAMETER InfName
    File name of the printer-driver INF to stage. Only this INF is installed - the vendor
    package also ships 32-bit, duplicate, fax/scan and null-driver INFs we don't want.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-PrinterDriver.ps1

.NOTES
    Author:  Oji (cmcleod1@umd.edu)
    Date:    2026-09-22
    Version: 1.1.0
    Log:     C:\ProgramData\StaffPrinters\Driver-Install.log
    Sentinel: HKLM\SOFTWARE\UMDLibraries\StaffPrinters\Driver  (Name, Version)
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DriverName = 'Canon Generic Plus UFR II',
    [string]$InfName = 'CNLB0MA64.INF'
)

begin {
    $ErrorActionPreference = 'Stop'

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess -and $PSCommandPath) {
        $ps64 = Join-Path $env:WINDIR 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
        & $ps64 -ExecutionPolicy Bypass -NoProfile -File $PSCommandPath -DriverName $DriverName -InfName $InfName
        exit $LASTEXITCODE
    }

    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $logDir = 'C:\ProgramData\StaffPrinters'
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force -WhatIf:$false | Out-Null }
    $sentinel = 'HKLM:\SOFTWARE\UMDLibraries\StaffPrinters\Driver'
}

process {
    $exitCode = 0
    $transcribing = $false
    try {
        try { Start-Transcript -Path (Join-Path $logDir 'Driver-Install.log') -Append -WhatIf:$false | Out-Null; $transcribing = $true } catch { }

        $infs = Get-ChildItem -Path (Join-Path $ScriptDir 'Driver') -Filter $InfName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $infs) { throw "$InfName not found under $ScriptDir\Driver" }

        foreach ($inf in $infs) {
            if ($PSCmdlet.ShouldProcess($inf.FullName, 'pnputil /add-driver /install')) {
                Write-Output "pnputil /add-driver $($inf.FullName)"
                & "$env:WINDIR\System32\pnputil.exe" /add-driver $inf.FullName /install | Out-Null
                if ($LASTEXITCODE -notin 0, 259, 3010) { Write-Warning "pnputil exit $LASTEXITCODE for $($inf.Name)" }
            }
        }

        if ($PSCmdlet.ShouldProcess($DriverName, 'Add-PrinterDriver')) {
            Add-PrinterDriver -Name $DriverName
        }

        if (-not $WhatIfPreference) {
            $installed = Get-PrinterDriver -Name $DriverName -ErrorAction Stop
            $version = $installed.DriverVersion
            # DriverVersion is a packed UInt64 - render it as a.b.c.d
            if ($version -is [uint64] -or $version -is [long]) {
                $v = [uint64]$version
                $version = '{0}.{1}.{2}.{3}' -f (($v -shr 48) -band 0xFFFF), (($v -shr 32) -band 0xFFFF), (($v -shr 16) -band 0xFFFF), ($v -band 0xFFFF)
            }
            if (-not (Test-Path $sentinel)) { New-Item -Path $sentinel -Force | Out-Null }
            Set-ItemProperty -Path $sentinel -Name 'Name' -Value $DriverName -Force
            Set-ItemProperty -Path $sentinel -Name 'Version' -Value "$version" -Force
            Write-Output "SUCCESS: '$DriverName' $version installed."
        }
    } catch {
        Write-Error "Driver install failed: $($_.Exception.Message)" -ErrorAction Continue
        $exitCode = 1
    } finally {
        if ($transcribing) { Stop-Transcript | Out-Null }
    }
    exit $exitCode
}
