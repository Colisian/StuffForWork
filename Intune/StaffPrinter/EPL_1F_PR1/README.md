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
IntuneWinAppUtil.exe -c ".\EPL_1F_PR1" -s Install-StaffPrinter.ps1 -o ".\_Output" -q
```

## Intune app settings
| Setting | Value |
|---|---|
| Name | `Staff Printer - EPL_1F_PR1` |
| Install command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-StaffPrinter.ps1` |
| Uninstall command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-StaffPrinter.ps1` |
| Install behavior | **System** |
| Return codes | 0 = Success, 1 = Failed |
| Detection | Custom script: `Detect-EPL_1F_PR1.ps1` (32-bit: No, enforce signature: No) |
| Dependency | `Staff Printer Driver - Canon Generic Plus UFR II` (auto-install: Yes) |
| Assignment | Device group |

## Verify on a test device
```powershell
Get-Printer -Name 'EPL_1F_PR1' | Format-List Name, DriverName, PortName, Location
Get-PrinterPort -Name 'IP_EPL_1F_PR1.resource.dyn.umd.edu' | Format-List Name, PrinterHostAddress, PortNumber
Resolve-DnsName 'EPL_1F_PR1.resource.dyn.umd.edu'
Test-NetConnection 'EPL_1F_PR1.resource.dyn.umd.edu' -Port 9100
Get-Content 'C:\ProgramData\StaffPrinters\EPL_1F_PR1-Install.log' -Tail 30
```

_Generated 2026-09-22 by `_Build\Build-StaffPrinterFolders.ps1` - edit the master CSV, not this file._
