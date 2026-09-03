# NVivo 15.5.2.4 — Microsoft Intune Win32 Package

## Table of Contents

- [[#Package Contents]]
- [[#Intune Configuration]]
- [[#Silent Activation Companion App]]
- [[#Detection]]
- [[#Logging and Verification]]
- [[#Licensing and Security Notes]]
- [[#Rebuild the Package]]
- [[#References]]

---

## Package Contents

> [[#Table of Contents|↑ Back to TOC]]

| Item | Purpose |
|---|---|
| `Output\Install-NVivo.intunewin` | Upload this file as a Windows app (Win32) |
| `Source\Install-NVivo.ps1` | Silent SYSTEM-context install wrapper |
| `Source\Uninstall-NVivo.ps1` | Silent uninstall wrapper |
| `Source\Detect-NVivo.ps1` | Custom Intune detection script |
| `Source\NVivo.x64.exe` | Lumivero NVivo 15.5.2.4 installer |

Installer SHA256: `32A2B6A7E2F448AA96819462E47F2090EE9000D6457A132BE7B5773DD9674DD7`

Generated package SHA256: `E87E0F2D79A5CEADC73C641B6C243DBDFA9B00CCB2A575060A8355EC84794E77`

Packaging tool: Microsoft Win32 Content Prep Tool `1.8.7.0`

---

## Intune Configuration

> [[#Table of Contents|↑ Back to TOC]]

Create a **Windows app (Win32)** and upload `Output\Install-NVivo.intunewin`.

| Setting | Value |
|---|---|
| Name | NVivo 15.5.2.4 |
| Publisher | Lumivero |
| App version | 15.5.2.4 |
| Install behavior | System |
| Device restart behavior | App install may force a device restart |
| 32-bit Windows | No |
| Minimum OS | Choose the oldest Windows x64 release supported by the UMD fleet and Lumivero |

**Install command (preferred Method A):**

```powershell
%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-NVivo.ps1
```

**Uninstall command:**

```powershell
%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-NVivo.ps1
```

Use the default Intune return codes, including `0` success, `1641` hard reboot, and `3010` soft reboot.

For Method B, paste the matching script into Intune's PowerShell installer field and configure it to run in a 64-bit PowerShell host. The package still must include `NVivo.x64.exe`; both wrappers locate bundled files by using `$PSScriptRoot` or the package working directory.

---

## Silent Activation Companion App

> [[#Table of Contents|↑ Back to TOC]]

The separate activation package is available at `Activation\Output\Activate-NVivo.intunewin`. Configure it as a SYSTEM-context Win32 app with this NVivo installer as an automatically installed dependency. See `Activation\README.md` for commands, detection, security handling, and license deactivation order.

---

## Detection

> [[#Table of Contents|↑ Back to TOC]]

Select **Use a custom detection script** and upload `Source\Detect-NVivo.ps1`.

The script requires both:

- NVivo 15 version 15.5.2.4 or newer in the Windows uninstall registry.
- The package sentinel at `HKLM\SOFTWARE\UMDLibraries\Intune\NVivo15`, proving this managed installer completed.

Configure **Run script as 32-bit process on 64-bit clients** as **No** and **Enforce script signature check** as **No**, unless the scripts are signed before upload.

---

## Logging and Verification

> [[#Table of Contents|↑ Back to TOC]]

Endpoint logs remain under:

```text
C:\ProgramData\UMDLibraries\NVivo\
```

Quick verification:

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\UMDLibraries\Intune\NVivo15'
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
    Where-Object DisplayName -Match '^NVivo(?:\s+15)?$' |
    Select-Object DisplayName, DisplayVersion, Publisher
```

Test install and uninstall under the SYSTEM account on a non-production pilot device before broad assignment. Review the wrapper logs above and Intune Management Extension logs under `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`.

---

## Licensing and Security Notes

> [[#Table of Contents|↑ Back to TOC]]

- This package installs the application but does not embed a license or enterprise key. Assign and activate licensing through the approved Lumivero process.
- The wrapper verifies the exact installer SHA256 before execution. Update the expected hash and version metadata when replacing the EXE.
- The source EXE was checked before packaging: valid DigiCert-backed signature from **Lumivero, LLC**.
- Pilot with CrowdStrike and Rapid7 enabled. Large InstallShield prerequisite extraction and child-process activity may create telemetry; investigate rather than adding broad exclusions.

---

## Rebuild the Package

> [[#Table of Contents|↑ Back to TOC]]

From an elevated PowerShell prompt:

```powershell
Set-Location 'C:\Users\cmcleod1\OneDrive - University of Maryland\Documents\Work\StuffForWork\Intune\NVivo\15.5.2.4'
.\Build-NVivoIntunePackage.ps1
```

The build script keeps the Microsoft content-prep utility outside `Source`, so it is not accidentally bundled into the `.intunewin` file.

---

## References

> [[#Table of Contents|↑ Back to TOC]]

- [Microsoft: Prepare Win32 app content for upload](https://learn.microsoft.com/en-us/intune/app-management/deployment/create-win32-package)
- [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
- [Lumivero NVivo](https://lumivero.com/products/nvivo/)
