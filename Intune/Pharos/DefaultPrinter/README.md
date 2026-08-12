# Default Printer — LIB-Mck2FWideFormat

Intune Win32 app that makes the Pharos wide-format queue **`LIB-Mck2FWideFormat`**
the default printer for **every user** of a machine — existing profiles, the
logged-in user, and any profile created later.

> **See also: [`PlatformScript/`](PlatformScript/README.md)** — a simpler,
> device-name-driven version that sets the right default per library location.
> A platform script running in user context gets per-user execution natively, so
> it needs none of the scheduled task and hive-loading machinery below. Prefer it
> unless you specifically need a dependency on the Pharos package or a supported
> uninstall.

> The queue name is `LIB-Mck2FWideFormat`, not `Mck2FloorWideFormat`. That is the
> `<printername>` inside `LIB-Mck2FloorWideFormat_for_x64.exe`, and it matches
> `ExpectedPrinters` in `PerLibrary/Definitions/McKeldin/Package.json`.

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
| `DefaultPrinter.json` | Bundled config — the only file to edit for a different queue |
| `install.cmd` / `uninstall.cmd` | Wrappers that force the 64-bit PowerShell host |

## Configuration

`DefaultPrinter.json`:

```json
{
  "PrinterName": "LIB-Mck2FWideFormat",
  "OverrideExistingDefault": true,
  "PrinterWaitSeconds": 60
}
```

- **`OverrideExistingDefault: true`** replaces a default the user picked themselves.
  Right for lab/public machines. Set to `false` for staff machines to only fill in
  a default where none exists.
- **`PrinterWaitSeconds`** — how long the logon task waits for the queue to appear
  before giving up, for machines still installing the Pharos package.

Changing the printer means editing **two** files: `DefaultPrinter.json` and the
hardcoded `$expectedPrinter` / `$expectedVersion` in `Detect-DefaultPrinter.ps1`.
Intune runs detection standalone with no access to the bundled JSON.

## Packaging

```powershell
IntuneWinAppUtil.exe -c ".\Intune\Pharos\DefaultPrinter" -s ".\DefaultPrinter.json" -o ".\Output"
```

`-s` is a required placeholder for script-driven installs; any bundled file works.

## Intune app settings

| Setting | Value |
|---|---|
| Install command | `install.cmd` |
| Uninstall command | `uninstall.cmd` |
| Install behavior | **System** |
| Device restart behavior | No specific action |
| Detection rule | Use a custom detection script → `Detect-DefaultPrinter.ps1` |
| Run script as 32-bit process | **No** |
| Enforce script signature check | **No** |

**Dependency (required):** add the Pharos McKeldin package as a *dependency* with
"automatically install" enabled. The install **fails with exit 1 if the queue is
not present** — it needs the real port name to write the registry values, and
guessing one would produce a broken default printer.

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

- `Windows\Device` = `LIB-Mck2FWideFormat,winspool,<port>`
- `Windows\LegacyDefaultPrinterMode` = `1`
- `Devices\LIB-Mck2FWideFormat` and `PrinterPorts\LIB-Mck2FWideFormat`
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
