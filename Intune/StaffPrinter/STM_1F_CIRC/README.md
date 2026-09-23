---
tags: [intune, printer, staff-printer]
printer: STM_1F_CIRC
status: Ready
---
# STM_1F_CIRC - Direct IP Printer (Intune Win32)

> [!note] HP (server: HP Universal Printing PCL 6 v7.8.0). Exact model TBD - UPD covers it. DDNS pending.

| Field | Value |
|---|---|
| Model | HP (model unknown) |
| Driver | `HP Universal Printing PCL 6` |
| Port | `IP_STM_1F_CIRC.resource.dyn.umd.edu` -> `STM_1F_CIRC.resource.dyn.umd.edu`:9100 (RAW) |
| Location | STEM Library - 1403M Circ |
| Current print-server target | `10.204.146.2` |

## Package
```powershell
.\_Build\New-StaffPrinterPackages.ps1 -IntuneWinAppUtil <path>\IntuneWinAppUtil.exe -Name STM_1F_CIRC
```

## Company Portal (App information)
| Setting | Value |
|---|---|
| Name | `Printer - STEM Library - 1403M Circ (STM_1F_CIRC)` |
| Description | `Adds the STM_1F_CIRC staff printer (STEM Library - 1403M Circ) to this computer for all users. Prints directly to the device - no print server.` |
| Publisher | `UMD Libraries IT` |
| Category | `Printers` |
| Show as featured app | No |
| Logo | `_Build\printer-icon.png` (if added) |
| Notes | `HP (model unknown) - STM_1F_CIRC.resource.dyn.umd.edu` |

## Intune app settings
| Setting | Value |
|---|---|
| Installer type | **PowerShell script** -> upload `Install-StaffPrinter.ps1` (from this folder) |
| Uninstaller type | **PowerShell script** -> upload `Uninstall-StaffPrinter.ps1` |
| Script options | Run as 32-bit: **No** - Enforce signature check: **No** |
| *(alt) Command line* | `powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-StaffPrinter.ps1` / `...\Uninstall-StaffPrinter.ps1` |
| Install behavior | **System** |
| Device restart behavior | No specific action |
| Return codes | Keep defaults (0 success, 1 fails naturally as "Failed") |
| Requirements | OS architecture: x64 only; minimum OS: Windows 10 22H2 |
| Detection | Custom script: `Detect-STM_1F_CIRC.ps1` (32-bit: No, enforce signature: No) |
| Dependency | `Staff Printer Driver - HP Universal Printing PCL 6` (auto-install: Yes) |
| Assignment | **Available for enrolled devices** -> Libraries staff **user** group; "Allow available uninstall" = Yes |

## Verify on a test device
```powershell
Get-Printer -Name 'STM_1F_CIRC' | Format-List Name, DriverName, PortName, Location
Get-PrinterPort -Name 'IP_STM_1F_CIRC.resource.dyn.umd.edu' | Format-List Name, PrinterHostAddress, PortNumber
Resolve-DnsName 'STM_1F_CIRC.resource.dyn.umd.edu'
Test-NetConnection 'STM_1F_CIRC.resource.dyn.umd.edu' -Port 9100
Get-Content 'C:\ProgramData\StaffPrinters\STM_1F_CIRC-Install.log' -Tail 30
```

_Generated 2026-09-22 by `_Build\Build-StaffPrinterFolders.ps1` - edit the master CSV, not this file._
