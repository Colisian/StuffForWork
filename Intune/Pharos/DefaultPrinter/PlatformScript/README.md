# Default Printer by Device Name — Platform Script

Sets each public PC's default printer from its **computer name**, using the same
hostname prefixes as the legacy PSADT deployment
(`Pharos\PharosApp Deploy\Deploy-Application.ps1:210-215`).

Runs in the **logged-on user's context at every sign-in**, which is what makes a
platform script the right shape for this job.

## Mapping

| Device name | Location | Default printer |
|---|---|---|
| `LIBRWKMCKP2WF*` | McKeldin 2nd Floor Wide Format | `LIB-Mck2FWideFormat` |
| `LIBRWKMCK*` | McKeldin Library | `LIB-MckBW` |
| `LIBRWKSTEM*` | STEM Library (EPSL) | `LIB-EPSLBW` |
| `LIBRWKART*` | Art Library | `LIB-ArtBW` |
| `LIBRWKMDRP*` | Maryland Room | `LIB-MarylandRoomBW` |
| `LIBRWKPAL*` | Performing Arts Library | `LIB-PALBW` |
| `LIBRWKARCH*` | Architecture Library | `LIB-ArchBW` |

A device matching no rule is left completely alone and reports success — it is
out of scope, not broken.

### Most-specific-wins, not first-match-wins

`LIBRWKMCKP2WF01` matches **both** `LIBRWKMCKP2WF*` and `LIBRWKMCK*`. The script
picks the rule with the longest literal prefix, so wide-format stations get the
plotter and every other McKeldin PC gets black & white — **regardless of the
order the rules appear in the table**. Reordering or inserting rules cannot
silently send patrons to the plotter.

Verified: with the table deliberately reordered so `LIBRWKMCK*` comes first,
first-match-wins returns `LIB-MckBW` for a wide-format station while the
implemented matcher still returns `LIB-Mck2FWideFormat`.

## Why `LegacyDefaultPrinterMode` matters

Windows 10/11 ship **"Let Windows manage my default printer"** enabled, which
re-points the default at the most recently used queue. Setting the default
without clearing it produces a change that works and then quietly reverts.

This is observable on the current fleet. On `LIBRWK93ZMR74`:

```text
LegacyDefaultPrinterMode = 0                              # Windows manages it
HKCU ...\Windows\Device  = \\LIBRPS403v...\MCK_4F_PR2     # what was set
Win32_Printer Default    = \\LIBRPS403v...\MCK_1F_PR4     # what is actually default
```

The two have already diverged. The script sets `LegacyDefaultPrinterMode = 1`
and treats "correct default **but** Windows still managing it" as non-compliant.

## Deploy as a platform script

**Devices → Scripts and remediations → Platform scripts → Add → Windows 10 and later**

| Setting | Value |
|---|---|
| Script location | `Set-DefaultPrinterByDevice.ps1` |
| Run this script using the logged on credentials | **Yes** |
| Enforce script signature check | No |
| Run script in 64 bit PowerShell Host | **Yes** |

Assign to your **device** groups for the public PCs.

> **"Run using logged on credentials = Yes" is the whole point.** It is what makes
> this a per-user setting applied to every user, and it is why no scheduled task,
> Active Setup entry, or offline hive loading is needed. Set it to No and the
> script writes SYSTEM's own HKCU, which no patron will ever see.

Platform scripts re-run at each sign-in when run in user context, so the mapping
self-applies to every new patron session.

## Alternative: deploy as a Remediation (recommended if you want reporting)

A default printer *drifts* — patrons change it, Windows overrides it. A platform
script only fires at sign-in and reports nothing beyond "the script ran."

**Devices → Scripts and remediations → Remediations**

| Field | File |
|---|---|
| Detection script | `Detect-DefaultPrinterByDevice.ps1` |
| Remediation script | `Set-DefaultPrinterByDevice.ps1` |

Same user-context and 64-bit settings. Schedule daily. You get per-device
compliance reporting and self-healing between logons.

Both scripts carry the same rule table — **edit them together.**

## Choosing between the three approaches

| | Platform script | Remediation | Win32 app (`..\` parent folder) |
|---|---|---|---|
| Per-user execution | Native | Native | Simulated via scheduled task + hive loading |
| Runs at | Each sign-in | Schedule + sign-in | Install time |
| Dependency on the Pharos package | No | No | **Yes** |
| Uninstall / revert | No | No | **Yes** |
| Reporting | Run status only | **Per-device compliance** | Detection rule |
| Self-heals drift | At next sign-in | **Yes** | No |

The Win32 app in the parent folder remains the option to use if you need Intune
to install the Pharos package *first* via a dependency, or need a supported
uninstall that restores each user's previous default.

## Handling the missing dependency

A platform script cannot be ordered after a Win32 app, so on a freshly imaged PC
it can run before the Pharos queues exist. Two mitigations are built in:

- `-PrinterWaitSeconds` (default 90) waits for the queue to appear.
- Running at every sign-in means the next patron fixes it.

If the queue never appears the script exits **1** with an actionable message:

```text
Print queue 'LIB-Mck2FWideFormat' did not appear within 90s.
Is the Pharos package for McKeldin 2nd Floor Wide Format assigned to this device?
```

## Logs

`C:\ProgramData\UMD\Pharos\Logs\DefaultPrinter-<username>.log`, falling back to
`%LOCALAPPDATA%\UMD\Logs\DefaultPrinter-User.log`.

A per-user filename means each user owns their own file, so a standard account
can append to it — ProgramData ACLs let users create files but not write to one
owned by SYSTEM. The log self-trims to the last 500 lines past 256 KB, since it
is appended at every sign-in on a shared PC.

## Verification

```powershell
# Dry run - reports the matched rule, changes nothing
.\Set-DefaultPrinterByDevice.ps1 -WhatIf

# Test the mapping against a hostname without owning that machine
$real = $env:COMPUTERNAME
try { $env:COMPUTERNAME = 'LIBRWKMCKP2WF01'; .\Set-DefaultPrinterByDevice.ps1 -WhatIf }
finally { $env:COMPUTERNAME = $real }

# Compliance check - exit 0 compliant, exit 1 needs remediation
.\Detect-DefaultPrinterByDevice.ps1; "exit=$LASTEXITCODE"

# Effective state for the current user
Get-CimInstance Win32_Printer -Filter 'Default=True' | Select-Object Name, PortName
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' |
    Select-Object Device, LegacyDefaultPrinterMode
```

## Caveats

- **Hostname naming is the weak point.** This machine is `LIBRWK93ZMR74` — a
  `LIBRWK` device with an asset-tag suffix rather than a location prefix. If any
  lab PC has been renamed to that scheme it will match no rule and silently keep
  whatever default it has. Confirm the public PCs still use `LIBRWK<LOCATION>*`
  before relying on this, or drive the mapping from Intune device groups instead.
- **Already-running applications** may keep the old default until restarted.
- The script never removes or installs a queue; it only changes which one is
  default.
- **Security:** no credentials, no network calls, no elevation. It runs as the
  standard user and writes only that user's HKCU. Nothing here should attract
  CrowdStrike or Rapid7 attention.
