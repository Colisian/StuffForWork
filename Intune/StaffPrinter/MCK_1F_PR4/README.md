---
tags: [intune, printer, staff-printer]
printer: MCK_1F_PR4
status: Ready
---
# MCK_1F_PR4 - Direct IP Printer (Intune Win32)

> [!note] DDNS pending.

| Field | Value |
|---|---|
| Model | Canon iR-ADV C3935i |
| Driver | `Canon Generic Plus UFR II` |
| Port | `IP_MCK_1F_PR4.resource.dyn.umd.edu` -> `MCK_1F_PR4.resource.dyn.umd.edu`:9100 (RAW) |
| Location | McKeldin - 1109 |
| Current print-server target | `10.204.152.17` |

## Package
```powershell
.\_Build\New-StaffPrinterPackages.ps1 -IntuneWinAppUtil <path>\IntuneWinAppUtil.exe -Name MCK_1F_PR4
```

## Company Portal (App information)
| Setting | Value |
|---|---|
| Name | `Printer - McKeldin - 1109 - Color (MCK_1F_PR4)` |
| Description | `Adds the MCK_1F_PR4 staff printer (McKeldin - 1109) to this computer for all users. Prints directly to the device - no print server.` |
| Publisher | `UMD Libraries IT` |
| Category | `Printers` |
| Show as featured app | No |
| Logo | `_Build\printer-icon.png` (if added) |
| Notes | `Canon iR-ADV C3935i - MCK_1F_PR4.resource.dyn.umd.edu` |

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
| Detection | Custom script: `Detect-MCK_1F_PR4.ps1` (32-bit: No, enforce signature: No) |
| Dependency | `Staff Printer Driver - Canon Generic Plus UFR II` (auto-install: Yes) |
| Assignment | **Available for enrolled devices** -> Libraries staff **user** group; "Allow available uninstall" = Yes |

## Verify on a test device
```powershell
Get-Printer -Name 'MCK_1F_PR4' | Format-List Name, DriverName, PortName, Location
Get-PrinterPort -Name 'IP_MCK_1F_PR4.resource.dyn.umd.edu' | Format-List Name, PrinterHostAddress, PortNumber
Resolve-DnsName 'MCK_1F_PR4.resource.dyn.umd.edu'
Test-NetConnection 'MCK_1F_PR4.resource.dyn.umd.edu' -Port 9100
Get-Content 'C:\ProgramData\StaffPrinters\MCK_1F_PR4-Install.log' -Tail 30
```

_Generated 2026-09-22 by `_Build\Build-StaffPrinterFolders.ps1` - edit the master CSV, not this file._
