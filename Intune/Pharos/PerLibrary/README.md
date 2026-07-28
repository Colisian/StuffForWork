# Pharos per-library Intune packages

## Decision

Use one lightweight, configuration-driven Win32 app per library/location. Do
not duplicate PSAppDeployToolkit for this deployment.

PSADT is useful when an install needs user prompts, application deferrals,
complex MSI handling, or session-aware UI. These Pharos packages run silently
as `SYSTEM`, invoke one or two vendor EXEs, and need deterministic verification.
The shared scripts here provide that without copying roughly 1 MB of toolkit
code and a hand-edited deployment script into every package.

The original Maryland Room wrapper is closer to the right approach, but this
implementation improves it by:

- supporting both a normal `-File` command and Intune's pasted-script flow;
- pinning the unsigned vendor EXEs to known SHA-256 hashes;
- verifying `Popup.exe` and the expected printer queues before detection;
- using a registry sentinel instead of a marker file;
- removing only the selected location's queues during uninstall;
- logging under `C:\ProgramData\UMD\Pharos\Logs`;
- generating all packages from shared scripts and per-location JSON.

## Package map

| Package ID | Intune app name | Vendor payload | Verified printer queues |
|---|---|---|---|
| `Architecture` | Pharos Printers - Architecture Library | `LIB-Arch_for_x64.exe` | `LIB-ArchBW`, `LIB-ArchColor` |
| `Art` | Pharos Printers - Art Library | `LIB-Art_for_x64.exe` | `LIB-ArtBW`, `LIB-ArtColor` |
| `EPSL` | Pharos Printers - STEM Library (EPSL) | `LIB-EPSL_for_x64.exe` | `LIB-EPSLBW`, `LIB-EPSLColor` |
| `MarylandRoom` | Pharos Printers - Maryland Room | `LIB-MarylandRoom_for_x64.exe` | `LIB-MarylandRoomBW`, `LIB-MarylandRoomColor` |
| `McKeldin` | Pharos Printers - McKeldin Library | `LIB-Mckeldin_for_x64.exe` and wide-format payload | `LIB-MckBW`, `LIB-MckColor`, `LIB-Mck2FWideFormat` |
| `PAL` | Pharos Printers - Performing Arts Library | `LIB-PAL_for_x64.exe` | `LIB-PALBW`, `LIB-PALColor` |

The old host-name script did not deploy the Architecture payload even though it
was bundled. Architecture is included here as its own package.

## Build and validate

Run from PowerShell 7.4+ or 64-bit Windows PowerShell 5.1:

```powershell
Set-Location 'C:\Users\cmcleod1\OneDrive - University of Maryland\Documents\Work\StuffForWork\Intune\Pharos\PerLibrary'

# Read-only validation: definitions, source files, and SHA-256 hashes
.\New-PharosIntunePackages.ps1 -ValidateOnly

# Create six package-ready source folders; do not build .intunewin files
.\New-PharosIntunePackages.ps1 -StageOnly

# Build all six .intunewin files into .\Output
.\New-PharosIntunePackages.ps1

# Build only selected locations
.\New-PharosIntunePackages.ps1 -PackageId McKeldin, MarylandRoom
```

The builder passes `Install-PharosLocation.ps1` to the required `-s` argument
and includes `Package.json`, both shared scripts, and only that location's EXE
payload(s). Change `-InstallerSourcePath`, `-IntuneWinAppUtilPath`, or
`-OutputPath` if the source folders move.

The `-StageOnly` command creates `.\PackageSources\<PackageId>` directories.
Point `IntuneWinAppUtil` at one of those folders and use
`Install-PharosLocation.ps1` as the `-s` placeholder when packaging manually.

## Intune Win32 app settings

Use these settings for every app.

**Program**

```text
Install command:
%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-PharosLocation.ps1

Uninstall command:
%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-PharosLocation.ps1

Install behavior: System
Device restart behavior: Determine behavior based on return codes
```

Keep return code `0` as Success, `1` as Failed, and `3010` as Soft reboot.
`SysNative` forces 64-bit Windows PowerShell from the 32-bit Intune Management
Extension, which also keeps the registry detection key in the 64-bit view.

**Requirements**

- Operating system architecture: 64-bit
- Minimum operating system: the oldest supported Windows 10/11 release in the
  public-PC fleet

**Detection**

Choose **Manually configure detection rules** and add a Registry rule:

| Setting | Value |
|---|---|
| Key path | `HKEY_LOCAL_MACHINE\SOFTWARE\UMD\Pharos\Packages\<PackageId>` |
| Value name | `Version` |
| Detection method | String comparison |
| Operator | Equals |
| Value | `9.2.10000.194` |
| Associated with a 32-bit app | No |

Replace `<PackageId>` with the ID in the package map. The sentinel is written
only after the installer hash, Popup client, and all configured queues verify.

**Assignments**

Assign each app as **Required** to its corresponding Intune device group. Prefer
device groups over user groups for public PCs so installation occurs before a
patron signs in. Use a small pilot device group for each location first.

## Migration from the current combined app

1. Upload the six new apps without assignments.
2. Pilot each package on at least one representative PC, including McKeldin
   wide-format printing.
3. Assign each new app as Required to its location device group.
4. Confirm the new apps report Installed and verify the queues locally.
5. Remove the **Required** assignment from the old combined app.
6. Do **not** assign the old combined app as Uninstall. Its command runs
   `Uninst.exe /s Popups`, which can remove the shared Popup client after a new
   package has installed.
7. Retire or delete the old app after deployment reporting is stable.

When moving a PC between libraries, add it to the new group first. After the new
package is installed, use an Uninstall assignment for the old per-library app
or remove the old queues manually. The new uninstall script removes only its
configured queues.

## Endpoint verification

Run in 64-bit Windows PowerShell as an administrator:

```powershell
# Shared Pharos client
Test-Path 'C:\Program Files (x86)\Pharos\Bin\Popup.exe'

# All Pharos queues currently present
Get-Printer | Where-Object Name -Like 'LIB-*' |
    Select-Object Name, DriverName, PortName

# Example detection state
Get-ItemProperty 'HKLM:\SOFTWARE\UMD\Pharos\Packages\McKeldin'

# Installer and uninstall logs
Get-ChildItem 'C:\ProgramData\UMD\Pharos\Logs\Pharos-*.log'
```

Test install and uninstall commands against extracted package content before
uploading:

```powershell
.\Install-PharosLocation.ps1 -WhatIf
.\Uninstall-PharosLocation.ps1 -WhatIf
```

`-WhatIf` validates configuration and source hashes but does not run vendor
installers, create queues, or change registry state.

## Security and operational notes

The supplied Pharos package EXEs report version `9.2.10000.194` and are not
Authenticode-signed. Their current SHA-256 hashes are pinned in each definition.
Treat any hash change as a new vendor payload: validate its origin, update the
version/hash intentionally, rebuild, and pilot again.

Printer-driver installation and a self-extracting unsigned EXE may be visible
to CrowdStrike or Rapid7. Pilot first and review detections. If an exception is
actually required, scope it to the validated hash and deployment context; do
not exclude the package directory, PowerShell, or the Pharos process broadly.

The selective uninstall deliberately leaves the shared Popup client, driver
store entries, and Pharos ports. This prevents one location app from breaking
another during assignment overlap. If complete product removal is ever needed,
use a separate, explicitly targeted cleanup app after confirming that no
per-library package remains assigned.
