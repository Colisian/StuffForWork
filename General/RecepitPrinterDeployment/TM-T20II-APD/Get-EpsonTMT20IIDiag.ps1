<#
.SYNOPSIS
    Collects Epson TM-T20II / APD5 printer diagnostics into one text file.

.DESCRIPTION
    Read-only. Run in an elevated PowerShell on the affected PC (and, for comparison,
    on a PC where the manual install works). Writes:
        C:\ProgramData\EpsonTMT20II\Diag-<COMPUTER>-<timestamp>.txt

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Get-EpsonTMT20IIDiag.ps1

.NOTES
    Author:  Oji
    Date:    2026-09-28
    Version: 1.1.0
#>
[CmdletBinding()]
param(
    [string]$OutputDir = 'C:\ProgramData\EpsonTMT20II'
)

begin {
    $ErrorActionPreference = 'Continue'
    if (-not (Test-Path $OutputDir)) { New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null }
    $outFile = Join-Path $OutputDir ('Diag-{0}-{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $sb = New-Object System.Text.StringBuilder

    function Add-Section {
        [CmdletBinding()]
        param([string]$Title, [scriptblock]$Body)
        [void]$sb.AppendLine(('=' * 20) + " $Title " + ('=' * 20))
        try { [void]$sb.AppendLine((& $Body | Out-String -Width 250).TrimEnd()) }
        catch { [void]$sb.AppendLine("ERROR: $_") }
        [void]$sb.AppendLine()
    }
}

end {
    Add-Section 'Context' {
        "Computer: $env:COMPUTERNAME  User: $(whoami)  Time: $(Get-Date -Format s)"
        "Admin: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators'))"
        "OS: $((Get-CimInstance Win32_OperatingSystem).Caption) $((Get-CimInstance Win32_OperatingSystem).BuildNumber)"
    }
    Add-Section 'Printers (all)' { Get-Printer | Format-Table Name, DriverName, PortName, PrinterStatus, Shared -AutoSize }
    Add-Section 'Printer ports (all)' { Get-PrinterPort | Format-Table Name, Description, PortMonitor -AutoSize }
    Add-Section 'Epson printer drivers' { Get-PrinterDriver | Where-Object Name -like '*EPSON*' | Format-Table Name, PrinterEnvironment, MajorVersion, InfPath -AutoSize }
    Add-Section 'Print monitors' { Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors' | Select-Object -ExpandProperty PSChildName }
    Add-Section 'EPSON Port Handler Monitor registry (recursive)' {
        $root = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\EPSON Port Handler Monitor'
        if (Test-Path $root) {
            Get-ChildItem $root -Recurse | ForEach-Object {
                "[$($_.Name)]"
                $_.Property | ForEach-Object -Begin { $k = $null } -Process { "  $_ = $((Get-ItemProperty -LiteralPath $_.PSPath -Name $_ -ErrorAction SilentlyContinue).$_)" }
            }
            Get-ItemProperty $root | Format-List
        }
        else { 'NOT PRESENT' }
    }
    Add-Section 'Queue driver data for TM-T20II queues' {
        Get-Printer | Where-Object DriverName -eq 'EPSON TM-T20II Receipt5' | ForEach-Object {
            $k = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers\$($_.Name)"
            "[$k]"; Get-ItemProperty $k | Format-List Name, Port, 'Printer Driver', Attributes, Status
        }
    }
    Add-Section 'Epson USB / printer PnP devices' {
        Get-PnpDevice | Where-Object { $_.InstanceId -match 'EPSON|USBPRINT|VID_04B8' -or $_.FriendlyName -match 'EPSON|TM-T20' } |
            Format-Table Status, Present, Class, FriendlyName, InstanceId -AutoSize
    }
    Add-Section 'Epson USB device driver binding (usbprint = Windows/v2, other = Epson)' {
        Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_04B8|USBPRINT\\EPSON' } | ForEach-Object {
            $props = Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_Service', 'DEVPKEY_Device_DriverInfPath', 'DEVPKEY_Device_DriverDesc', 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue
            [pscustomobject]@{
                InstanceId = $_.InstanceId
                Status     = $_.Status
                Service    = ($props | Where-Object KeyName -eq 'DEVPKEY_Device_Service').Data
                DriverInf  = ($props | Where-Object KeyName -eq 'DEVPKEY_Device_DriverInfPath').Data
                DriverDesc = ($props | Where-Object KeyName -eq 'DEVPKEY_Device_DriverDesc').Data
                Problem    = ($props | Where-Object KeyName -eq 'DEVPKEY_Device_ProblemCode').Data
            }
        } | Format-Table -AutoSize
    }
    Add-Section 'Printer status detail' {
        Get-CimInstance Win32_Printer -Filter "DriverName='EPSON TM-T20II Receipt5'" |
            Format-List Name, PortName, PrinterStatus, ExtendedPrinterStatus, DetectedErrorState, WorkOffline, Status
    }
    Add-Section 'Last reboot' { (Get-CimInstance Win32_OperatingSystem).LastBootUpTime }
    Add-Section 'Epson services' { Get-Service | Where-Object { $_.DisplayName -match 'EPSON|Port Communication' -or $_.Name -match 'PCSVC|EPSON' } | Format-Table Name, DisplayName, Status, StartType -AutoSize }
    Add-Section 'Spooler' { Get-Service Spooler | Format-Table Name, Status, StartType -AutoSize }
    Add-Section 'TCP 2291 (PCS)' { Get-NetTCPConnection -LocalPort 2291 -ErrorAction SilentlyContinue | Format-Table LocalAddress, LocalPort, State, OwningProcess -AutoSize }
    Add-Section 'Uninstall entries (Epson)' {
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
            ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
            Where-Object DisplayName -match 'EPSON' | Format-Table DisplayName, DisplayVersion, UninstallString -AutoSize
    }
    Add-Section 'EPSON APD5 registry' {
        'HKLM:\SOFTWARE\EPSON', 'HKLM:\SOFTWARE\WOW6432Node\EPSON' | Where-Object { Test-Path $_ } | ForEach-Object {
            Get-ChildItem $_ -Recurse -ErrorAction SilentlyContinue | ForEach-Object { "[$($_.Name)]"; ($_ | Get-ItemProperty | Format-List | Out-String).Trim() }
        }
    }
    Add-Section 'Intune sentinel' { Get-ItemProperty 'HKLM:\SOFTWARE\UMDLibraries\Intune\EpsonTMT20II-APD' -ErrorAction SilentlyContinue | Format-List Version, InstallDate, Installer }
    Add-Section 'Install.log (last 80 lines)' { Get-Content (Join-Path $OutputDir 'Install.log') -Tail 80 -ErrorAction SilentlyContinue }
    Add-Section 'Epson Setup.log files' {
        Get-ChildItem "${env:ProgramFiles(x86)}\EPSON", "$env:ProgramFiles\EPSON", "$env:WINDIR\Temp", "$env:ProgramData\EPSON" -Recurse -Include 'Setup.log', 'CopyInstallLog.txt' -ErrorAction SilentlyContinue |
            ForEach-Object { "--- $($_.FullName) ($($_.LastWriteTime))"; Get-Content $_.FullName -Tail 60 }
    }
    Add-Section 'PrintService Admin log (last 25 warnings/errors)' {
        Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-PrintService/Admin'; Level = 2, 3 } -MaxEvents 25 -ErrorAction SilentlyContinue |
            Format-Table TimeCreated, Id, Message -AutoSize -Wrap
    }
    Add-Section 'Intune AppWorkload log (Epson lines)' {
        Get-ChildItem 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs' -Filter 'AppWorkload*.log' -ErrorAction SilentlyContinue |
            Select-String -Pattern 'Epson|TMT20II|exit code|detection' | Select-Object -Last 40 | ForEach-Object { $_.Line }
    }

    [IO.File]::WriteAllText($outFile, $sb.ToString())
    Write-Output $sb.ToString()
    Write-Output "Saved: $outFile"
}
