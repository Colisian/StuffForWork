---
tags: [intune, printer, staff-printer]
printer: MCK_5F_PR1
status: Ready
---
# MCK_5F_PR1 - Direct IP Printer (Intune Win32)

> [!note] DDNS pending. Inventory room 4233 on a 5F queue - confirm.

| Field | Value |
|---|---|
| Model | Canon iR-ADV C3935i |
| Driver | `Canon Generic Plus UFR II` |
| Port | `IP_MCK_5F_PR1.resource.dyn.umd.edu` -> `MCK_5F_PR1.resource.dyn.umd.edu`:9100 (RAW) |
| Location | McKeldin - Humanities 4233 |
| Current print-server target | `10.204.152.24` |

## Package
```powershell
IntuneWinAppUtil.exe -c ".\MCK_5F_PR1" -s Install-StaffPrinter.ps1 -o ".\_Output" -q
```

## Intune app settings
| Setting | Value |
|---|---|
| Name | `Staff Printer - MCK_5F_PR1` |
| Install command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-StaffPrinter.ps1` |
| Uninstall command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-StaffPrinter.ps1` |
| Install behavior | **System** |
| Return codes | 0 = Success, 1 = Failed |
| Detection | Custom script: `Detect-MCK_5F_PR1.ps1` (32-bit: No, enforce signature: No) |
| Dependency | `Staff Printer Driver - Canon Generic Plus UFR II` (auto-install: Yes) |
| Assignment | Device group |

## Verify on a test device
```powershell
Get-Printer -Name 'MCK_5F_PR1' | Format-List Name, DriverName, PortName, Location
Get-PrinterPort -Name 'IP_MCK_5F_PR1.resource.dyn.umd.edu' | Format-List Name, PrinterHostAddress, PortNumber
Resolve-DnsName 'MCK_5F_PR1.resource.dyn.umd.edu'
Test-NetConnection 'MCK_5F_PR1.resource.dyn.umd.edu' -Port 9100
Get-Content 'C:\ProgramData\StaffPrinters\MCK_5F_PR1-Install.log' -Tail 30
```

_Generated 2026-09-22 by `_Build\Build-StaffPrinterFolders.ps1` - edit the master CSV, not this file._
