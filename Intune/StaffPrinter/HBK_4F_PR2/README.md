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
IntuneWinAppUtil.exe -c ".\HBK_4F_PR2" -s Install-StaffPrinter.ps1 -o ".\_Output" -q
```

## Intune app settings
| Setting | Value |
|---|---|
| Name | `Staff Printer - HBK_4F_PR2` |
| Install command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-StaffPrinter.ps1` |
| Uninstall command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-StaffPrinter.ps1` |
| Install behavior | **System** |
| Return codes | 0 = Success, 1 = Failed |
| Detection | Custom script: `Detect-HBK_4F_PR2.ps1` (32-bit: No, enforce signature: No) |
| Dependency | `Staff Printer Driver - HP Universal Printing PCL 6` (auto-install: Yes) |
| Assignment | Device group |

## Verify on a test device
```powershell
Get-Printer -Name 'HBK_4F_PR2' | Format-List Name, DriverName, PortName, Location
Get-PrinterPort -Name 'IP_HBK_4F_PR2.resource.dyn.umd.edu' | Format-List Name, PrinterHostAddress, PortNumber
Resolve-DnsName 'HBK_4F_PR2.resource.dyn.umd.edu'
Test-NetConnection 'HBK_4F_PR2.resource.dyn.umd.edu' -Port 9100
Get-Content 'C:\ProgramData\StaffPrinters\HBK_4F_PR2-Install.log' -Tail 30
```

_Generated 2026-09-22 by `_Build\Build-StaffPrinterFolders.ps1` - edit the master CSV, not this file._
