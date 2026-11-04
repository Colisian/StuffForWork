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
    Version: 1.2.0
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
        $relaunchArgs = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', $PSCommandPath) + @('-DriverName', $DriverName, '-InfName', $InfName)
        if ($WhatIfPreference) { $relaunchArgs += '-WhatIf' }
        & $ps64 @relaunchArgs
        exit $LASTEXITCODE
    }

    # Intune's uploaded-script method may run this from its own temp folder (PSScriptRoot set
    # but wrong) or with no file at all (PSScriptRoot empty); CWD is the package either way.
    $ScriptDir = @($PSScriptRoot, (Get-Location).Path) |
        Where-Object { $_ -and (Test-Path (Join-Path $_ 'Driver')) } | Select-Object -First 1
    if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
    $pnputil = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { "$env:WINDIR\Sysnative\pnputil.exe" } else { "$env:WINDIR\System32\pnputil.exe" }

    $logDir = 'C:\ProgramData\StaffPrinters'
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force -WhatIf:$false | Out-Null }
    $sentinel = 'HKLM:\SOFTWARE\UMDLibraries\StaffPrinters\Driver'

    function ConvertTo-DriverVersion {
        # DriverVersion is a packed UInt64 (16 bits per part) - return it as [version]
        [CmdletBinding()]
        param([uint64]$Value)
        [version]('{0}.{1}.{2}.{3}' -f ($Value -shr 48), (($Value -shr 32) -band 0xFFFF), (($Value -shr 16) -band 0xFFFF), ($Value -band 0xFFFF))
    }
}

end {
    $exitCode = 0
    $transcribing = $false
    try {
        try { Start-Transcript -Path (Join-Path $logDir 'Driver-Install.log') -Append -WhatIf:$false | Out-Null; $transcribing = $true } catch { }

        $inf = Get-ChildItem -Path (Join-Path $ScriptDir 'Driver') -Filter $InfName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $inf) { throw "$InfName not found under $ScriptDir\Driver" }

        # Packaged version = first DriverVer= line of the INF ([Version] section)
        $verLine = Select-String -Path $inf.FullName -Pattern '^\s*DriverVer\s*=\s*[^,]+,\s*([\d.]+)' | Select-Object -First 1
        if (-not $verLine) { throw "No DriverVer found in $($inf.Name)" }
        $packagedVersion = [version]$verLine.Matches[0].Groups[1].Value
        Write-Output "Packaged: '$DriverName' $packagedVersion ($($inf.Name))"

        $current = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($current) { Write-Output "Currently registered: $(ConvertTo-DriverVersion $current.DriverVersion) from $($current.InfPath)" }

        if ($PSCmdlet.ShouldProcess($inf.FullName, 'pnputil /add-driver /install')) {
            & $pnputil /add-driver $inf.FullName /install | Out-Null
            # 259 = staged, no matching PnP device - expected for printers
            if ($LASTEXITCODE -notin 0, 259, 3010) { Write-Warning "pnputil exit $LASTEXITCODE for $($inf.Name)" }
        }

        # Register THIS package explicitly. Add-PrinterDriver -Name alone keeps an older
        # same-name driver already on the PC (e.g. v3.20 pulled down by print-server connections).
        if ($PSCmdlet.ShouldProcess($DriverName, "Add-PrinterDriver $packagedVersion")) {
            $staged = Get-WindowsDriver -Online | Where-Object {
                (Split-Path $_.OriginalFileName -Leaf) -eq $inf.Name -and [version]$_.Version -eq $packagedVersion
            } | Select-Object -First 1
            if (-not $staged) { throw "pnputil did not stage $($inf.Name) $packagedVersion into the driver store." }
            Write-Output "Add-PrinterDriver -InfPath $($staged.OriginalFileName)"
            Add-PrinterDriver -Name $DriverName -InfPath $staged.OriginalFileName
        }

        if (-not $WhatIfPreference) {
            $installed = Get-PrinterDriver -Name $DriverName -ErrorAction Stop | Select-Object -First 1
            $version = ConvertTo-DriverVersion $installed.DriverVersion
            if ($version -lt $packagedVersion) { throw "'$DriverName' is still $version after install (expected $packagedVersion)." }
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
