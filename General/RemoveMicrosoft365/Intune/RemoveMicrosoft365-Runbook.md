# Runbook — Remove Consumer Microsoft 365 (Intune Win32)

> [!info] Summary
> Removes OEM-bundled consumer Office Click-to-Run (`O365HomePremRetail`, `OneNoteFreeRetail`, all languages) from new endpoints via ODT, packaged as an Intune Win32 app. Assigned **Required** so it runs during enrollment/ESP, before the user sees the device.

**Author**: Colin McLeod · **Date**: 2026-07-14 · **Version**: 1.0.0

---

## Why Win32 (not Remediation)

| | Win32 app | Remediation |
|---|---|---|
| Runs during ESP/enrollment | ✅ Yes (Required assignment) | ❌ Schedule-only, post-enrollment |
| Retry on failure | ✅ Built-in retry cycle | Re-runs on schedule |
| Can bundle ODT `setup.exe` | ✅ Inside `.intunewin` | ❌ Must download at runtime |
| Dependency chaining (e.g., M365 Apps enterprise depends on this) | ✅ | ❌ |
| Runtime allowance | 60 min default | Suited to short checks; stdout <2048 chars |

Consumer Office doesn't reinstall itself after removal — this is a one-time state change, which is the Win32 model. Use a Remediation instead only if you need continuous drift enforcement fleet-wide.

## Package layout

```
General\RemoveMicrosoft365\Intune\
├── Source\                      ← contents of the .intunewin
│   ├── Install.ps1              ← install wrapper (guards, ODT staging, exit codes)
│   ├── Uninstall.ps1            ← required stub, no-op, exit 0
│   ├── remove.xml               ← ODT Remove All configuration
│   └── setup.exe                ← ODT binary — YOU add this (see step 1)
├── Detection\
│   └── Detect-ConsumerOffice.ps1  ← upload in Detection rules blade (NOT packaged)
└── RemoveMicrosoft365-Runbook.md
```

## Step 1 — Stage ODT setup.exe

Download the latest [Office Deployment Tool](https://www.microsoft.com/en-us/download/details.aspx?id=49117), run the self-extractor, and copy `setup.exe` into `Source\`:

```powershell
# From the ODT extract folder
Copy-Item .\setup.exe "General\RemoveMicrosoft365\Intune\Source\setup.exe"
```

> [!warning] The script has a download fallback to a **version-pinned** Microsoft URL that will eventually go stale. Always bundle `setup.exe` — the fallback is a safety net, not the plan.

## Step 2 — Build the .intunewin

```powershell
# https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool
.\IntuneWinAppUtil.exe -c ".\Intune\Source" -s "Install.ps1" -o ".\Intune\Output" -q
# Produces: .\Intune\Output\Install.intunewin
```

## Step 3 — Create the Win32 app in Intune

**Apps → Windows → Add → Windows app (Win32)**, upload `Install.intunewin`.

### App information
- **Name**: `Remove Consumer Microsoft 365 (ODT)`
- **Publisher**: `UMD Libraries ITFO`

### Program
| Setting | Value |
|---|---|
| Install command | `"%windir%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` |
| Uninstall command | `"%windir%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Install behavior | **System** |
| Device restart behavior | Determine behavior based on return codes |

Return codes: `0` = Success · `3010` = Soft reboot · `1` = Failure (leave the other defaults).

> `%windir%\Sysnative\...` forces 64-bit PowerShell from the 32-bit Intune Management Extension — registry reads under `HKLM:\SOFTWARE\Microsoft\Office\ClickToRun` need the 64-bit view.

### Requirements
- OS architecture: 64-bit · Minimum OS: Windows 10 22H2 (or your baseline)

### Detection rules
- **Rules format**: *Use a custom detection script*
- **Script file**: `Detection\Detect-ConsumerOffice.ps1`
- Run as 32-bit: **No** · Enforce signature check: **No**

### Assignment
- **Required** → new-endpoint / lab device group.
- If M365 Apps for enterprise is deployed as a Win32 app, add this app as a **dependency** of it (auto-install) so removal always precedes the enterprise install.
- If devices go through Autopilot ESP with blocking apps, consider adding this to the blocking list so users never see consumer Office.

## Safety notes

- `Remove All="TRUE"` strips **every** C2R product. `Install.ps1` aborts (exit 1) if it finds non-consumer product IDs (e.g. `O365ProPlusRetail`) alongside the consumer SKUs — those devices surface as install failures in Intune and need a targeted `remove.xml` by hand.
- Detection keys only on consumer SKUs, so a later enterprise Office install does **not** flip the app to "not installed" and re-trigger `Remove All`.
- `FORCEAPPSHUTDOWN=TRUE` kills running Office apps without prompting — fine for new endpoints; think twice before targeting in-use devices.
- No security-stack impact expected: ODT is a signed Microsoft binary; CrowdStrike may log the process tree (`powershell.exe → setup.exe`) but this matches normal Office servicing behavior.

## Verification

On a target device (as admin):

```powershell
# Consumer SKUs gone? (key absent entirely on a fully clean device)
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty ProductReleaseIds

# Wrapper + ODT logs
Get-ChildItem C:\ProgramData\OfficeRemoval
Get-Content  C:\ProgramData\OfficeRemoval\Install.log -Tail 30

# What Intune thought happened
Get-Content "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload.log" -Tail 100 |
    Select-String 'Remove Consumer'

# Dry-run the detection logic locally
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Detection\Detect-ConsumerOffice.ps1; $LASTEXITCODE
```

Expected end state: `ProductReleaseIds` empty/absent, `Install.log` ends with `ODT exit code: 0`, Intune shows the app **Installed**.
