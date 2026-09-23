<#
.SYNOPSIS
    Generates one Intune Win32 package folder per staff printer from the master CSV.

.DESCRIPTION
    For every row in StaffPrinters-DirectIP.csv, creates/refreshes ..\<Name>\ containing:
      Install-StaffPrinter.ps1    (shared template, copied)
      Uninstall-StaffPrinter.ps1  (shared template, copied)
      printer.csv                 (that printer's row - the only per-printer data file)
      Detect-<Name>.ps1           (upload to Intune as the custom detection script)
      README.md                   (Intune settings for that app)
    Re-run whenever the master CSV or the templates change. Generated files are overwritten.

.PARAMETER MasterCsv
    Master printer list. Default: StaffPrinters-DirectIP.csv next to this script.

.PARAMETER OutputRoot
    Parent folder for the per-printer folders. Default: the StaffPrinter folder (..).

.EXAMPLE
    .\Build-StaffPrinterFolders.ps1 -WhatIf

.NOTES
    Author:  Oji (cmcleod1@umd.edu)
    Date:    2026-09-22
    Version: 1.0.0
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$MasterCsv,
    [string]$OutputRoot
)

begin {
    $ErrorActionPreference = 'Stop'
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    if (-not $MasterCsv)  { $MasterCsv  = Join-Path $ScriptDir 'StaffPrinters-DirectIP.csv' }
    if (-not $OutputRoot) { $OutputRoot = Split-Path $ScriptDir -Parent }
    $templateDir = Join-Path $ScriptDir 'Template'
    $today = Get-Date -Format 'yyyy-MM-dd'
}

process {
    $rows = Import-Csv -Path $MasterCsv
    $detectTemplate = Get-Content -Path (Join-Path $templateDir 'Detect-Printer.ps1.template') -Raw

    foreach ($row in $rows) {
        $name = $row.Name.Trim()
        $dir  = Join-Path $OutputRoot $name
        if (-not $PSCmdlet.ShouldProcess($dir, 'Generate printer package folder')) { continue }

        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

        Copy-Item -Path (Join-Path $templateDir 'Install-StaffPrinter.ps1')   -Destination $dir -Force
        Copy-Item -Path (Join-Path $templateDir 'Uninstall-StaffPrinter.ps1') -Destination $dir -Force

        $row | Select-Object Name, DriverName, PortAddress, Location, Comment |
            Export-Csv -Path (Join-Path $dir 'printer.csv') -NoTypeInformation -Encoding UTF8

        $detect = $detectTemplate.
            Replace('__NAME__', $name).
            Replace('__DRIVER__', $row.DriverName.Trim().Replace("'", "''")).
            Replace('__FQDN__', $row.PortAddress.Trim()).
            Replace('__DATE__', $today)
        Set-Content -Path (Join-Path $dir "Detect-$name.ps1") -Value $detect -Encoding UTF8

        $statusLine = switch ($row.Status) {
            'NeedsInfo'   { "> [!warning] NEEDS INFO - do not package yet`n> $($row.Notes)" }
            'Blocked-DNS' { "> [!warning] BLOCKED - ``$($row.PortAddress)`` does not resolve yet; do not deploy until it does.`n> $($row.Notes)" }
            default       { if ($row.Notes) { "> [!note] $($row.Notes)" } else { '' } }
        }

        $colorMode = if ($row.Model -match '\bC\d{4}|Color') { 'Color' } elseif ($row.Model -match '\d{4}i') { 'B&W' } else { '' }
        $displayName = "Printer - $($row.Location)$(if ($colorMode) { " - $colorMode" }) ($name)"

        $readme = @"
---
tags: [intune, printer, staff-printer]
printer: $name
status: $($row.Status)
---
# $name - Direct IP Printer (Intune Win32)

$statusLine

| Field | Value |
|---|---|
| Model | $($row.Model) |
| Driver | ``$($row.DriverName)`` |
| Port | ``IP_$($row.PortAddress)`` -> ``$($row.PortAddress)``:9100 (RAW) |
| Location | $($row.Location) |
| Current print-server target | ``$($row.CurrentServerTarget)`` |

## Package
``````powershell
.\_Build\New-StaffPrinterPackages.ps1 -IntuneWinAppUtil <path>\IntuneWinAppUtil.exe -Name $name
``````

## Company Portal (App information)
| Setting | Value |
|---|---|
| Name | ``$displayName`` |
| Description | ``Adds the $name staff printer ($($row.Location)) to this computer for all users. Prints directly to the device - no print server.`` |
| Publisher | ``UMD Libraries IT`` |
| Category | ``Printers`` |
| Show as featured app | No |
| Logo | ``_Build\printer-icon.png`` (if added) |
| Notes | ``$($row.Model) - $($row.PortAddress)`` |

## Intune app settings
| Setting | Value |
|---|---|
| Install command | ``powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-StaffPrinter.ps1`` |
| Uninstall command | ``powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-StaffPrinter.ps1`` |
| Install behavior | **System** |
| Device restart behavior | No specific action |
| Return codes | Keep defaults (0 success, 1 fails naturally as "Failed") |
| Requirements | OS architecture: x64 only; minimum OS: Windows 10 22H2 |
| Detection | Custom script: ``Detect-$name.ps1`` (32-bit: No, enforce signature: No) |
| Dependency | ``Staff Printer Driver - $($row.DriverName)`` (auto-install: Yes) |
| Assignment | **Available for enrolled devices** -> Libraries staff **user** group; "Allow available uninstall" = Yes |

## Verify on a test device
``````powershell
Get-Printer -Name '$name' | Format-List Name, DriverName, PortName, Location
Get-PrinterPort -Name 'IP_$($row.PortAddress)' | Format-List Name, PrinterHostAddress, PortNumber
Resolve-DnsName '$($row.PortAddress)'
Test-NetConnection '$($row.PortAddress)' -Port 9100
Get-Content 'C:\ProgramData\StaffPrinters\$name-Install.log' -Tail 30
``````

_Generated $today by ``_Build\Build-StaffPrinterFolders.ps1`` - edit the master CSV, not this file._
"@
        Set-Content -Path (Join-Path $dir 'README.md') -Value $readme -Encoding UTF8
        Write-Output "Generated $name ($($row.Status))"
    }
}
