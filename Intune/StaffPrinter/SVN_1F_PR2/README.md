---
tags: [intune, printer, staff-printer]
printer: SVN_1F_PR2
status: NeedsInfo
---
# SVN_1F_PR2 - Direct IP Printer (Intune Win32)

> [!warning] NEEDS INFO - do not package yet
> Server queue is SVN_1F_PR1 (10.204.130.139) but inventory calls the device SVN_1F_PR2. Pick the final name. DDNS name does not resolve yet.

| Field | Value |
|---|---|
| Model | Canon iR-ADV C3935i |
| Driver | `Canon Generic Plus UFR II` |
| Port | `IP_SVN_1F_PR2.resource.dyn.umd.edu` -> `SVN_1F_PR2.resource.dyn.umd.edu`:9100 (RAW) |
| Location | Severn Library - 208 |
| Current print-server target | `10.204.130.139` |

## Package
```powershell
IntuneWinAppUtil.exe -c ".\SVN_1F_PR2" -s Install-StaffPrinter.ps1 -o ".\_Output" -q
```

## Intune app settings
| Setting | Value |
|---|---|
| Name | `Staff Printer - SVN_1F_PR2` |
| Install command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-StaffPrinter.ps1` |
| Uninstall command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-StaffPrinter.ps1` |
| Install behavior | **System** |
| Return codes | 0 = Success, 1 = Failed |
| Detection | Custom script: `Detect-SVN_1F_PR2.ps1` (32-bit: No, enforce signature: No) |
| Dependency | `Staff Printer Driver - Canon Generic Plus UFR II` (auto-install: Yes) |
| Assignment | Device group |

## Verify on a test device
```powershell
Get-Printer -Name 'SVN_1F_PR2' | Format-List Name, DriverName, PortName, Location
Get-PrinterPort -Name 'IP_SVN_1F_PR2.resource.dyn.umd.edu' | Format-List Name, PrinterHostAddress, PortNumber
Resolve-DnsName 'SVN_1F_PR2.resource.dyn.umd.edu'
Test-NetConnection 'SVN_1F_PR2.resource.dyn.umd.edu' -Port 9100
Get-Content 'C:\ProgramData\StaffPrinters\SVN_1F_PR2-Install.log' -Tail 30
```

_Generated 2026-09-22 by `_Build\Build-StaffPrinterFolders.ps1` - edit the master CSV, not this file._
