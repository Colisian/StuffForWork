---
tags: [intune, printer, staff-printer]
printer: HBK_3F_PR1
status: Ready
---
# HBK_3F_PR1 - Direct IP Printer (Intune Win32)

> [!note] DDNS resolves.

| Field | Value |
|---|---|
| Model | Canon iR-ADV C3935i |
| Driver | `Canon Generic Plus UFR II` |
| Port | `IP_HBK_3F_PR1.resource.dyn.umd.edu` -> `HBK_3F_PR1.resource.dyn.umd.edu`:9100 (RAW) |
| Location | Hornbake - 3210F |
| Current print-server target | `hbk_3f_pr1.resource.dyn.umd.edu` |

## Package
```powershell
.\_Build\New-StaffPrinterPackages.ps1 -IntuneWinAppUtil <path>\IntuneWinAppUtil.exe -Name HBK_3F_PR1
```

## Company Portal (App information)
| Setting | Value |
|---|---|
| Name | `Printer - Hornbake - 3210F - Color (HBK_3F_PR1)` |
| Description | `Adds the HBK_3F_PR1 staff printer (Hornbake - 3210F) to this computer for all users. Prints directly to the device - no print server.` |
| Publisher | `UMD Libraries IT` |
| Category | `Printers` |
| Show as featured app | No |
| Logo | `_Build\printer-icon.png` (if added) |
| Notes | `Canon iR-ADV C3935i - HBK_3F_PR1.resource.dyn.umd.edu` |

## Intune app settings
| Setting | Value |
|---|---|
| Install command | `powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-StaffPrinter.ps1` |
| Uninstall command | `powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-StaffPrinter.ps1` |
| Install behavior | **System** |
| Device restart behavior | No specific action |
| Return codes | Keep defaults (0 success, 1 fails naturally as "Failed") |
| Requirements | OS architecture: x64 only; minimum OS: Windows 10 22H2 |
| Detection | Custom script: `Detect-HBK_3F_PR1.ps1` (32-bit: No, enforce signature: No) |
| Dependency | `Staff Printer Driver - Canon Generic Plus UFR II` (auto-install: Yes) |
| Assignment | **Available for enrolled devices** -> Libraries staff **user** group; "Allow available uninstall" = Yes |

## Verify on a test device
```powershell
Get-Printer -Name 'HBK_3F_PR1' | Format-List Name, DriverName, PortName, Location
Get-PrinterPort -Name 'IP_HBK_3F_PR1.resource.dyn.umd.edu' | Format-List Name, PrinterHostAddress, PortNumber
Resolve-DnsName 'HBK_3F_PR1.resource.dyn.umd.edu'
Test-NetConnection 'HBK_3F_PR1.resource.dyn.umd.edu' -Port 9100
Get-Content 'C:\ProgramData\StaffPrinters\HBK_3F_PR1-Install.log' -Tail 30
```

_Generated 2026-09-22 by `_Build\Build-StaffPrinterFolders.ps1` - edit the master CSV, not this file._
