---
tags: [intune, printer, driver]
---
# Staff Printer Driver - HP Universal Printing PCL 6 (Intune Win32)

Shared driver app. Every staff printer app lists this as a **dependency**, so the driver is uploaded once and removing one printer never removes the driver.

## What to drop in here
Put the **extracted x64** driver in `.\Driver\` so the `.inf` is somewhere under it:

```
_Driver-HPUniversalPCL6\
  Install-PrinterDriver.ps1
  Uninstall-PrinterDriver.ps1
  Detect-PrinterDriver.ps1
  Driver\            <- extracted HP Universal Printing PCL 6 (x64) - folder containing the .inf
```

Confirm the model string inside the INF matches `HP Universal Printing PCL 6` exactly:
```powershell
Select-String -Path .\Driver\**\*.inf -Pattern '"HP Universal Printing PCL 6"' -List
```
If it differs, change `$DriverName` in all three scripts **and** the `DriverName` column in `_Build\StaffPrinters-DirectIP.csv`, then re-run the generator.

## Package
```powershell
.\_Build\New-StaffPrinterPackages.ps1 -IntuneWinAppUtil <path>\IntuneWinAppUtil.exe -Name _Driver-HPUniversalPCL6
```

## Intune app settings
| Setting | Value |
|---|---|
| Name | `Staff Printer Driver - HP Universal Printing PCL 6` |
| Installer type | **PowerShell script** -> upload `Install-PrinterDriver.ps1` |
| Uninstaller type | **PowerShell script** -> upload `Uninstall-PrinterDriver.ps1` |
| Script options | Run as 32-bit: **No** - Enforce signature check: **No** |
| *(alt) Command line* | `powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-PrinterDriver.ps1` / `...\Uninstall-PrinterDriver.ps1` |
| Install behavior | System |
| Detection | Custom script `Detect-PrinterDriver.ps1` |
| Assignment | **None** - Intune installs it automatically as a dependency; it never appears in Company Portal |

## Verify
```powershell
Get-PrinterDriver -Name 'HP Universal Printing PCL 6' | Format-List Name, DriverVersion, InfPath
Get-ItemProperty 'HKLM:\SOFTWARE\UMDLibraries\StaffPrinters\Driver'
Get-Content C:\ProgramData\StaffPrinters\Driver-Install.log -Tail 30
```

> [!note] HP UPD specifics
> Extract the **HP Universal Print Driver PCL6 (x64)** zip (do not run its installer). The model name in `hpcu*.inf` may be version-suffixed, e.g. `HP Universal Printing PCL 6 (v7.x.x)` - use whatever string the INF lists, and set it everywhere (`$DriverName` in these 3 scripts + the master CSV for HBK_4F_PR2 and STM_1F_CIRC).
