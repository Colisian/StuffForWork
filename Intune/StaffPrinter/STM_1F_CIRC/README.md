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
IntuneWinAppUtil.exe -c ".\STM_1F_CIRC" -s Install-StaffPrinter.ps1 -o ".\_Output" -q
```

## Intune app settings
| Setting | Value |
|---|---|
| Name | `Staff Printer - STM_1F_CIRC` |
| Install command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-StaffPrinter.ps1` |
| Uninstall command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-StaffPrinter.ps1` |
| Install behavior | **System** |
| Return codes | 0 = Success, 1 = Failed |
| Detection | Custom script: `Detect-STM_1F_CIRC.ps1` (32-bit: No, enforce signature: No) |
| Dependency | `Staff Printer Driver - HP Universal Printing PCL 6` (auto-install: Yes) |
| Assignment | Device group |

## Verify on a test device
```powershell
Get-Printer -Name 'STM_1F_CIRC' | Format-List Name, DriverName, PortName, Location
Get-PrinterPort -Name 'IP_STM_1F_CIRC.resource.dyn.umd.edu' | Format-List Name, PrinterHostAddress, PortNumber
Resolve-DnsName 'STM_1F_CIRC.resource.dyn.umd.edu'
Test-NetConnection 'STM_1F_CIRC.resource.dyn.umd.edu' -Port 9100
Get-Content 'C:\ProgramData\StaffPrinters\STM_1F_CIRC-Install.log' -Tail 30
```

_Generated 2026-09-22 by `_Build\Build-StaffPrinterFolders.ps1` - edit the master CSV, not this file._
