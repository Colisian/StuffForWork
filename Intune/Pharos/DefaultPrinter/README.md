# Default Printer by Device Name — Win32 app

Intune Win32 app that sets the default printer for **every user** of a machine —
existing profiles, the logged-in user, and any profile created later — choosing
the queue from the **computer name**.

> **Alternative: [`PlatformScript/`](PlatformScript/README.md)** — the same
> mapping delivered as an Intune platform script. It gets per-user execution
> natively and needs none of the scheduled task or hive-loading machinery below,
> but it runs **once per user** with no dependency ordering and no uninstall.
> Use this Win32 app when you want a dependency on the Pharos package, a
> supported uninstall, or per-device detection reporting.

> **Queue names carry no `LIB-` prefix.** Pharos strips it when creating the
> local spool queue, even though it appears in the vendor EXE filename and its
> manifest. The wide-format queue also drops "Floor": the installer is
> `LIB-Mck2FloorWideFormat_for_x64.exe`, the queue is `Mck2FWideFormat`. All
> names confirmed on real hardware — see
> [`PlatformScript/PharosDiscovery/`](PlatformScript/PharosDiscovery/).

## Why this needs three moving parts

The default printer is a **per-user (HKCU)** setting, but a Win32 app installs as
SYSTEM. One SYSTEM-context registry write cannot reach every user, so the install
does three things:

| Part | Covers |
|---|---|
| Direct writes to every existing profile hive + `C:\Users\Default\NTUSER.DAT` | Users who already have a profile, and brand-new profiles |
| Logon scheduled task `\UMD\Set-DefaultPrinter` (principal `BUILTIN\Users`) | Every user at every logon — self-heals if a profile resets or the queue installs later |
| `LegacyDefaultPrinterMode = 1` | Windows 10/11 ships **"Let Windows manage my default printer"** on, which silently re-points the default at the last-used queue. Without this the setting will not stick. |

## Files

| File | Role |
|---|---|
| `Install-DefaultPrinter.ps1` | Install script (SYSTEM) |
| `Uninstall-DefaultPrinter.ps1` | Uninstall script (SYSTEM) |
| `Detect-DefaultPrinter.ps1` | Custom detection script |
| `Set-DefaultPrinter.User.ps1` | Payload staged to ProgramData, run per user at logon |
| `DefaultPrinter.json` | Bundled config — the device-name rule table, the only file to edit |
| `install.cmd` / `uninstall.cmd` | Wrappers that force the 64-bit PowerShell host |

## Configuration

All mapping lives in `DefaultPrinter.json`. Verified against real hardware:

| Device name | Location | Default printer |
|---|---|---|
| `LIBRWKMCKP2WF*` | McKeldin 2nd Floor Wide Format | `Mck2FWideFormat` |
| `LIBRWKMCK*` | McKeldin Library | `McKeldinBW` |
| `LIBRWKSTEM*` | STEM Library (**EPSL** queues) | `EPSLBW` |
| `LIBRWKART*` | Art Library | `ArtBW` |
| `LIBRWKPAL*` | Performing Arts Library | `PALBW` |
| `LIBRWKARCH*` | Architecture Library | `ArchBW` |
| `LIBRWKMDRP*` | Maryland Room | `MarylandRoomBW` → `LIB-MarylandRoomBW` ⚠️ unverified |

`PrinterName` is a **candidate list**, tried in order; the first queue that
actually exists wins. Maryland Room keeps two candidates because no discovery has
been run there.

**Rule matching is most-specific-wins, not first-match-wins.** `LIBRWKMCKP2WF01`
matches both `LIBRWKMCKP2WF*` and `LIBRWKMCK*`; the longer literal prefix takes
it, so reordering the array cannot silently send patrons to the plotter.

**STEM-named devices carry EPSL queues on purpose** — the library was renamed,
the print queues were not.

Other settings:

- **`OverrideExistingDefault: true`** replaces a default the user picked
  themselves. Right for lab/public machines. Set to `false` for staff machines to
  only fill in a default where none exists.
- **`PrinterWaitSeconds`** — how long the logon task waits for the queue to
  appear, for machines still installing the Pharos package.

**Changing the mapping** means editing `DefaultPrinter.json` **and** bumping
`Version` there plus `$expectedVersion` in `Detect-DefaultPrinter.ps1`. Detection
runs standalone with no access to the bundled JSON, and the version bump is what
makes Intune re-run the install on already-configured devices.

## Packaging

### What goes in the `.intunewin`

Package **this folder only** — five files. Do **not** include `PlatformScript\`
(that is the alternative deployment, plus the discovery captures):

```text
DefaultPrinter\
  install.cmd                    <- install command
  uninstall.cmd                  <- uninstall command
  Install-DefaultPrinter.ps1
  Uninstall-DefaultPrinter.ps1
  Set-DefaultPrinter.User.ps1    <- staged to ProgramData, run per user at logon
  DefaultPrinter.json            <- the device-name rule table
```

`Detect-DefaultPrinter.ps1` is **not** packaged — it is uploaded separately as
the custom detection script. Including it does no harm, but it is never used
from inside the package.

### Build

```powershell
$src = "C:\...\StuffForWork\Intune\Pharos\DefaultPrinter"
$stage = "$env:TEMP\DefaultPrinterPkg"

# Stage without PlatformScript\ so the discovery captures are not shipped
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item "$src\*" -Destination $stage -Force -Exclude 'PlatformScript','README.md'

IntuneWinAppUtil.exe -c $stage -s "$stage\install.cmd" -o ".\Output"
```

`-s` is a required placeholder for script-driven installs; pointing it at
`install.cmd` keeps the setup file and the install command consistent.

## Intune app settings

**Program**

```text
Install command:
install.cmd

Uninstall command:
uninstall.cmd

Install behavior:          System
Device restart behavior:   No specific action
```

Both `.cmd` wrappers resolve `%SystemRoot%\Sysnative\...\powershell.exe` when it
exists, so the scripts always run in the 64-bit host regardless of how the Intune
Management Extension launches them. That matters because `HKLM\SOFTWARE` is
WOW64-redirected and the detection sentinel would otherwise land in
`Wow6432Node`.

If you prefer explicit commands over the wrappers, use:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-DefaultPrinter.ps1
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-DefaultPrinter.ps1
```

**Return codes** — keep the defaults: `0` Success, `1` Failed, `3010` Soft reboot.

**Requirements**

- Operating system architecture: 64-bit
- Minimum OS: the oldest Windows 10/11 release in the public-PC fleet

**Detection**

Choose **Use a custom detection script** and upload `Detect-DefaultPrinter.ps1`.

| Setting | Value |
|---|---|
| Run script as 32-bit process on 64-bit clients | **No** |
| Enforce script signature check | **No** |

**Dependencies (required):** add the Pharos package for each location you assign
this to, with "automatically install" enabled. On an in-scope device the install
**fails with exit 1 if none of that location's candidate queues exist** — it
needs the real port name to write the registry values, and guessing one would
produce a broken default printer.

**Assignments:** assign as Required to the same device groups that receive the
Pharos packages. Devices whose name matches no rule are handled gracefully — see
below — so a slightly broad assignment is safe.

### Devices outside the rule table

A device matching no `Pattern` is **not** an error. The install stages the
payload, registers the logon task, writes a sentinel of `(out of scope)`, and
exits 0, so Intune reports Installed rather than retrying forever. No default
printer is touched on that machine.

The payload and task are still staged deliberately: a machine later renamed into
scope starts working at the next logon without redeploying the app.

### Method B — pasted PowerShell installer

Both scripts resolve their directory with
`if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }`, so they also
work pasted into Intune's Win32 "PowerShell script installer" boxes. If you use
that flow, confirm the app is set to run 64-bit — the `.cmd` wrappers are what
normally force this, and the detection sentinel would otherwise land in
`Wow6432Node`. (The scripts read and write HKLM through an explicit 64-bit
registry view, so this is belt-and-braces.)

## What it writes

**Machine:**

- `HKLM:\SOFTWARE\UMD\Pharos\DefaultPrinter` — detection sentinel
  (`PrinterName`, `Version`, `PayloadPath`, `TaskName`, `ConfiguredOnUtc`)
- `C:\ProgramData\UMD\Pharos\Set-DefaultPrinter.User.ps1` + `DefaultPrinter.json`
- Scheduled task `\UMD\Set-DefaultPrinter`

**Per user** (under `Software\Microsoft\Windows NT\CurrentVersion\`):

- `Windows\Device` = `<resolved queue>,winspool,<port>`
- `Windows\LegacyDefaultPrinterMode` = `1`
- `Devices\<resolved queue>` and `PrinterPorts\<resolved queue>`
- `Software\UMD\Pharos\DefaultPrinter` — backup of the previous default

The backup is written **once** and never overwritten, so redeploying cannot lose
a user's original default. Uninstall restores it (and removes `Device` entirely
if the profile had no default before).

## Logs

| Context | Path |
|---|---|
| Install / uninstall (SYSTEM) | `C:\ProgramData\UMD\Pharos\Logs\DefaultPrinter-Install.log` |
| Per-user logon task | `%LOCALAPPDATA%\UMD\Logs\DefaultPrinter-User.log` |

The per-user log lives in the profile because ProgramData ACLs let standard users
create files but not append to one owned by SYSTEM.

## Verification

```powershell
# Detection — expect output text and exit 0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Detect-DefaultPrinter.ps1
"exit=$LASTEXITCODE"

# Sentinel
Get-ItemProperty 'HKLM:\SOFTWARE\UMD\Pharos\DefaultPrinter'

# Logon task
Get-ScheduledTask -TaskName 'Set-DefaultPrinter' -TaskPath '\UMD\' |
    Select-Object TaskName, State

# Current user's effective default
Get-CimInstance Win32_Printer -Filter 'Default=True' | Select-Object Name, PortName
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' |
    Select-Object Device, LegacyDefaultPrinterMode

# Dry run without changing anything
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DefaultPrinter.ps1 -WhatIf
```

Both install and uninstall support `-WhatIf`.

## Notes and caveats

- **Already-signed-in users:** the install writes their loaded hive directly, so
  the default changes without a logon. Applications already running may keep the
  old default until restarted.
- **Roaming/redirected profiles:** a hive that cannot be loaded is logged as a
  WARN and skipped; the logon task picks that user up at their next sign-in.
- **The print queue is never touched.** Uninstall only gives back the previous
  default — removing the queue is the Pharos package's job.
- **Security:** no credentials, no network calls, no binaries. The scheduled task
  runs as the standard user at `-RunLevel Limited`, and its payload lives in
  ProgramData where non-admins cannot modify it. Nothing here should draw
  CrowdStrike or Rapid7 attention — though transient `reg load`/`reg unload` of
  user hives by a SYSTEM process is the one behavior worth knowing about if a
  detection ever fires during a deployment window.
