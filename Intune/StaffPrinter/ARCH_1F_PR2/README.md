---
tags: [intune, printer, staff-printer]
printer: ARCH_1F_PR2
status: Ready
---
# ARCH_1F_PR2 - Direct IP Printer (Intune Win32)

> [!note] Shared staff/public MFP - uses the public-facing hostname (same as print-server port). DDNS pending.

| Field | Value |
|---|---|
| Model | Canon iR-ADV C3935i |
| Driver | `Canon Generic Plus UFR II` |
| Port | `IP_LIB-ArchCanonMFP1.resource.dyn.umd.edu` -> `LIB-ArchCanonMFP1.resource.dyn.umd.edu`:9100 (RAW) |
| Location | Architecture Library - 1102 |
| Current print-server target | `lib-archcanonmfp1.resource.dyn.umd.edu` |

## Package
```powershell
IntuneWinAppUtil.exe -c ".\ARCH_1F_PR2" -s Install-StaffPrinter.ps1 -o ".\_Output" -q
```

## Intune app settings
| Setting | Value |
|---|---|
| Name | `Staff Printer - ARCH_1F_PR2` |
| Install command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-StaffPrinter.ps1` |
| Uninstall command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-StaffPrinter.ps1` |
| Install behavior | **System** |
| Return codes | 0 = Success, 1 = Failed |
| Detection | Custom script: `Detect-ARCH_1F_PR2.ps1` (32-bit: No, enforce signature: No) |
| Dependency | `Staff Printer Driver - Canon Generic Plus UFR II` (auto-install: Yes) |
| Assignment | Device group |

## Verify on a test device
```powershell
Get-Printer -Name 'ARCH_1F_PR2' | Format-List Name, DriverName, PortName, Location
Get-PrinterPort -Name 'IP_LIB-ArchCanonMFP1.resource.dyn.umd.edu' | Format-List Name, PrinterHostAddress, PortNumber
Resolve-DnsName 'LIB-ArchCanonMFP1.resource.dyn.umd.edu'
Test-NetConnection 'LIB-ArchCanonMFP1.resource.dyn.umd.edu' -Port 9100
Get-Content 'C:\ProgramData\StaffPrinters\ARCH_1F_PR2-Install.log' -Tail 30
```

_Generated 2026-09-22 by `_Build\Build-StaffPrinterFolders.ps1` - edit the master CSV, not this file._
