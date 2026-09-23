---
tags: [intune, printer, staff-printer]
printer: EPL_1F_PR1
status: NeedsInfo
---
# EPL_1F_PR1 - Direct IP Printer (Intune Win32)

> [!warning] NEEDS INFO - do not package yet
> Server queue is actually EPL_1F_PR1_BW (10.204.146.3) - old EPL_1F_PR1.ps1 points at a queue that does not exist. DDNS name does not resolve yet.

| Field | Value |
|---|---|
| Model | Canon iR-ADV 4925i |
| Driver | `Canon Generic Plus UFR II` |
| Port | `IP_EPL_1F_PR1.resource.dyn.umd.edu` -> `EPL_1F_PR1.resource.dyn.umd.edu`:9100 (RAW) |
| Location | STEM Library - 1403L |
| Current print-server target | `10.204.146.3` |

## Package
```powershell
.\_Build\New-StaffPrinterPackages.ps1 -IntuneWinAppUtil <path>\IntuneWinAppUtil.exe -Name EPL_1F_PR1
```

## Company Portal (App information)
| Setting | Value |
|---|---|
| Name | `Printer - STEM Library - 1403L - B&W (EPL_1F_PR1)` |
| Description | `Adds the EPL_1F_PR1 staff printer (STEM Library - 1403L) to this computer for all users. Prints directly to the device - no print server.` |
| Publisher | `UMD Libraries IT` |
| Category | `Printers` |
| Show as featured app | No |
| Logo | `_Build\printer-icon.png` (if added) |
| Notes | `Canon iR-ADV 4925i - EPL_1F_PR1.resource.dyn.umd.edu` |

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
| Detection | Custom script: `Detect-EPL_1F_PR1.ps1` (32-bit: No, enforce signature: No) |
| Dependency | `Staff Printer Driver - Canon Generic Plus UFR II` (auto-install: Yes) |
| Assignment | **Available for enrolled devices** -> Libraries staff **user** group; "Allow available uninstall" = Yes |

## Verify on a test device
```powershell
Get-Printer -Name 'EPL_1F_PR1' | Format-List Name, DriverName, PortName, Location
Get-PrinterPort -Name 'IP_EPL_1F_PR1.resource.dyn.umd.edu' | Format-List Name, PrinterHostAddress, PortNumber
Resolve-DnsName 'EPL_1F_PR1.resource.dyn.umd.edu'
Test-NetConnection 'EPL_1F_PR1.resource.dyn.umd.edu' -Port 9100
Get-Content 'C:\ProgramData\StaffPrinters\EPL_1F_PR1-Install.log' -Tail 30
```

_Generated 2026-09-22 by `_Build\Build-StaffPrinterFolders.ps1` - edit the master CSV, not this file._
