---
tags: [intune, printer, staff-printer]
printer: HBK_4F_PR2
status: Ready
---
# HBK_4F_PR2 - Direct IP Printer (Intune Win32)

> [!note] HP (server driver: HP LJ300-400 color MFP M375-M475 PCL6 Class Driver) - using HP UPD. Room TBD (Location cosmetic). DDNS pending.

| Field | Value |
|---|---|
| Model | HP Color LaserJet Pro MFP M375/M475 series |
| Driver | `HP Universal Printing PCL 6` |
| Port | `IP_HBK_4F_PR2.resource.dyn.umd.edu` -> `HBK_4F_PR2.resource.dyn.umd.edu`:9100 (RAW) |
| Location | Hornbake - 4th Floor |
| Current print-server target | `10.205.3.17` |

## Package
```powershell
.\_Build\New-StaffPrinterPackages.ps1 -IntuneWinAppUtil <path>\IntuneWinAppUtil.exe -Name HBK_4F_PR2
```

## Company Portal (App information)
| Setting | Value |
|---|---|
| Name | `Printer - Hornbake - 4th Floor - Color (HBK_4F_PR2)` |
| Description | `Adds the HBK_4F_PR2 staff printer (Hornbake - 4th Floor) to this computer for all users. Prints directly to the device - no print server.` |
| Publisher | `UMD Libraries IT` |
| Category | `Printers` |
| Show as featured app | No |
| Logo | `_Build\printer-icon.png` (if added) |
| Notes | `HP Color LaserJet Pro MFP M375/M475 series - HBK_4F_PR2.resource.dyn.umd.edu` |

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
| Detection | Custom script: `Detect-HBK_4F_PR2.ps1` (32-bit: No, enforce signature: No) |
| Dependency | `Staff Printer Driver - HP Universal Printing PCL 6` (auto-install: Yes) |
| Assignment | **Available for enrolled devices** -> Libraries staff **user** group; "Allow available uninstall" = Yes |

## Verify on a test device
```powershell
Get-Printer -Name 'HBK_4F_PR2' | Format-List Name, DriverName, PortName, Location
Get-PrinterPort -Name 'IP_HBK_4F_PR2.resource.dyn.umd.edu' | Format-List Name, PrinterHostAddress, PortNumber
Resolve-DnsName 'HBK_4F_PR2.resource.dyn.umd.edu'
Test-NetConnection 'HBK_4F_PR2.resource.dyn.umd.edu' -Port 9100
Get-Content 'C:\ProgramData\StaffPrinters\HBK_4F_PR2-Install.log' -Tail 30
```

_Generated 2026-09-22 by `_Build\Build-StaffPrinterFolders.ps1` - edit the master CSV, not this file._
