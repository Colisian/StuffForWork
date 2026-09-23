---
tags: [intune, printer, driver]
---
# Staff Printer Driver - Canon Generic Plus UFR II (Intune Win32)

Shared driver app. Every staff printer app lists this as a **dependency**, so the driver is uploaded once and removing one printer never removes the driver.

## What to drop in here
Put the **extracted x64** driver in `.\Driver\` so the `.inf` is somewhere under it:

```
_Driver-CanonGenericPlusUFRII\
  Install-PrinterDriver.ps1
  Uninstall-PrinterDriver.ps1
  Detect-PrinterDriver.ps1
  Driver\            <- extracted Canon Generic Plus UFR II (x64) - folder containing the .inf
```

Confirm the model string inside the INF matches `Canon Generic Plus UFR II` exactly:
```powershell
Select-String -Path .\Driver\**\*.inf -Pattern '"Canon Generic Plus UFR II"' -List
```
If it differs, change `$DriverName` in all three scripts **and** the `DriverName` column in `_Build\StaffPrinters-DirectIP.csv`, then re-run the generator.

## Package
```powershell
IntuneWinAppUtil.exe -c ".\_Driver-CanonGenericPlusUFRII" -s Install-PrinterDriver.ps1 -o ".\_Output" -q
```

## Intune app settings
| Setting | Value |
|---|---|
| Name | `Staff Printer Driver - Canon Generic Plus UFR II` |
| Install command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-PrinterDriver.ps1` |
| Uninstall command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-PrinterDriver.ps1` |
| Install behavior | System |
| Detection | Custom script `Detect-PrinterDriver.ps1` |
| Assignment | None needed - installed automatically as a dependency |

## Verify
```powershell
Get-PrinterDriver -Name 'Canon Generic Plus UFR II' | Format-List Name, DriverVersion, InfPath
Get-ItemProperty 'HKLM:\SOFTWARE\UMDLibraries\StaffPrinters\Driver'
Get-Content C:\ProgramData\StaffPrinters\Driver-Install.log -Tail 30
```
