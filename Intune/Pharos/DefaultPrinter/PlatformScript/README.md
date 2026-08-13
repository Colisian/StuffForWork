# Default Printer by Device Name — Platform Script

Sets each public PC's default printer from its **computer name**, using the same
hostname prefixes as the legacy PSADT deployment
(`Pharos\PharosApp Deploy\Deploy-Application.ps1:210-215`).

Runs in the **logged-on user's context, once per user per device**, which is what
makes a platform script the right shape for this job.

## Mapping

Each rule carries **candidate queue names**, tried in order; the first one that
actually exists on the device wins.

| Device name | Location | Default printer | Verified |
|---|---|---|---|
| `LIBRWKMCKP2WF*` | McKeldin 2nd Floor Wide Format | `Mck2FWideFormat` | ✅ `LIBRWKMCKP2WF1` |
| `LIBRWKMCK*` | McKeldin Library | `McKeldinBW` | ✅ `LIBRWKMCKP2WF1` |
| `LIBRWKSTEM*` | STEM Library (**EPSL** queues) | `EPSLBW` | ✅ `LIBRWKSTEMP1F1` |
| `LIBRWKART*` | Art Library | `ArtBW` | ✅ Art PC |
| `LIBRWKPAL*` | Performing Arts Library | `PALBW` | ✅ `LIBRWKPALP1F2` |
| `LIBRWKARCH*` | Architecture Library | `ArchBW` | ✅ `LIBRWKARCHP1F1` |
| `LIBRWKMDRP*` | Maryland Room | `MarylandRoomBW` → `LIB-MarylandRoomBW` | ⚠️ **unverified** |

**STEM-named devices carry EPSL queues on purpose** — the library was renamed but
the print queues were not. `LIBRWKSTEM*` → `EPSLBW` is correct, not a typo.

A device matching no rule is left completely alone and reports success — it is
out of scope, not broken.

### Why two names per location

**The script must match the spooler queue name (`Win32_Printer.Name`), which is
not always the label shown in Settings > Printers & scanners:**

| Situation | `Win32_Printer.Name` | Settings shows |
|---|---|---|
| Locally installed queue (what the Pharos EXEs create) | `McKeldinBW` | `McKeldinBW` |
| Connection to a shared print server queue | `\\LIBRPS403v\MCK_1F_PR4` | `MCK_1F_PR4` |
| RDP / Windows 365 redirected | `McKeldin Library - Color (redirected 1)` | belongs to the **client**, not this PC |

### The `LIB-` prefix does not exist on real queues

Discovery output in [`PharosDiscovery/`](PharosDiscovery/) settles this. The
actual local queues, identified by `PortName = PharosPopupPort`:

```text
LIBRWKMCKP2WF1  ->  Mck2FWideFormat, McKeldinBW, McKeldinColor
LIBRWKSTEMP1F1  ->  EPSLBW, EPSLColor
Art PC          ->  ArtBW, ArtColor
LIBRWKPALP1F2   ->  PALBW, PALColor
LIBRWKARCHP1F1  ->  ArchBW, ArchColor
```

The device names also confirm a `LIBRWK<SITE>P<floor>F<n>` convention, which is
what the prefix rules rely on.

**`LIB-` appears only on the vendor installer filenames and inside their
manifests — Pharos strips it when creating the local spool queue.** Reading
`<printername>` out of the EXE was therefore misleading; only on-device
discovery is authoritative.

McKeldin differs beyond the prefix as well: the queue is `McKeldinBW`, not the
`MckBW` recorded in `PerLibrary/Definitions/McKeldin/Package.json`.

The friendly names (`McKeldin Library - Black & White`) turned out to be **RDP
redirections from the technician's own client PC**, present in every capture
regardless of which lab machine was inspected. They are not queues on the lab
PCs at all, which is why both scripts exclude `(redirected N)`.

### Redirected queues never count

A queue ending in `(redirected N)` belongs to the remote client and disappears
with the session, so making it the default would be meaningless. Both scripts
exclude them. Verified: on a machine where `McKeldin Library - Black & White`
exists *only* as a redirected queue, detection correctly reports non-compliant.

## Confirm the real queue names first

Run on a representative lab PC of each location, as the patron-facing user:

```powershell
.\Get-PharosPrinterInventory.ps1
```

It lists every queue with the exact string to match, classifies each as
`Pharos Popup (local)` / `Print server connection` / `RDP-redirected` / `Local`,
and reports the current default and `LegacyDefaultPrinterMode`. Read-only.

Then trim each rule to the single name that machine actually reports.

### Most-specific-wins, not first-match-wins

`LIBRWKMCKP2WF01` matches **both** `LIBRWKMCKP2WF*` and `LIBRWKMCK*`. The script
picks the rule with the longest literal prefix, so wide-format stations get the
plotter and every other McKeldin PC gets black & white — **regardless of the
order the rules appear in the table**. Reordering or inserting rules cannot
silently send patrons to the plotter.

Verified: with the table deliberately reordered so `LIBRWKMCK*` comes first,
first-match-wins returns `McKeldinBW` for a wide-format station while the
implemented matcher still returns `Mck2FWideFormat`.

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

### Execution frequency — read this before relying on it

**Platform scripts run once, not on a schedule and not at every logon.** There is
no "run at every sign-in" option. With logged-on credentials the Intune
Management Extension tracks execution **per user per device**, so:

| Event | Script runs? |
|---|---|
| New patron signs in for the first time on this PC | **Yes** |
| Same patron signs in again later | No |
| Patron changes their default printer mid-session | No |
| Script fails | Retries 3 times over later check-ins |
| You re-upload a modified script | Yes, once more per user |

For a public PC that is mostly fine — every new profile gets the default set. The
gap is a **returning** patron who has since changed their default, and any drift
after the script has run for them.

If that gap matters, deploy as a Remediation instead (below). It is the same
script and it *does* repeat on a schedule.

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
| Runs | **Once per user**, at that user's first sign-in | On a schedule, per user | Once at install, then a logon task |
| Covers a brand-new patron profile | **Yes** | **Yes** | **Yes** |
| Corrects a returning patron who changed their default | **No** | **Yes** | Yes (logon task) |
| Dependency on the Pharos package | No | No | **Yes** |
| Uninstall / revert | No | No | **Yes** |
| Reporting | Run status only | **Per-device compliance** | Detection rule |

The Win32 app in the parent folder remains the option to use if you need Intune
to install the Pharos package *first* via a dependency, or need a supported
uninstall that restores each user's previous default.

## Handling the missing dependency

A platform script cannot be ordered after a Win32 app, so on a freshly imaged PC
it can run before the Pharos queues exist. Two mitigations are built in:

- `-PrinterWaitSeconds` (default 90) waits for the queue to appear.
- A failed run is retried 3 times over later check-ins, and the next new patron
  gets a fresh run regardless.

If the queue never appears the script exits **1** with an actionable message:

```text
Print queue 'Mck2FWideFormat' did not appear within 90s.
Is the Pharos package for McKeldin 2nd Floor Wide Format assigned to this device?
```

## Logs

`C:\ProgramData\UMD\Pharos\Logs\DefaultPrinter-<username>.log`, falling back to
`%LOCALAPPDATA%\UMD\Logs\DefaultPrinter-User.log`.

A per-user filename means each user owns their own file, so a standard account
can append to it — ProgramData ACLs let users create files but not write to one
owned by SYSTEM. The log self-trims to the last 500 lines past 256 KB, which
matters if you deploy as a Remediation and it runs on a schedule.

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

- **Maryland Room is still unverified.** Run `Get-PharosPrinterInventory.ps1` on
  one of its PCs and reduce that rule to the single real name. Until then it
  falls back through its candidate list, and a mismatch surfaces as exit 1 with
  the queue names logged — it cannot set the wrong printer.
- **Black & white is an assumption.** Every machine inspected had
  `LegacyDefaultPrinterMode = 0`, so its current default is drift, not policy —
  two had drifted to `Adobe PDF`. That said, Art and Architecture both currently
  sit on their Color queue, which may or may not reflect what those libraries
  want. Worth a quick confirmation; it is one word per rule to change.
- **Two repo files carry the wrong queue names** and predate this work — see
  "Known bad queue names elsewhere in the repo" below.
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

## Queue names corrected elsewhere in the repo (2026-08-12)

The same `LIB-` mistake existed in code predating this work. Both were live
faults, and both are now fixed:

| File | Was | Now | Fault it caused |
|---|---|---|---|
| `PerLibrary/Definitions/{Architecture,Art,EPSL,McKeldin,PAL}/Package.json` | `LIB-ArchBW`, `LIB-MckBW`, … | `ArchBW`, `McKeldinBW`, … | `Install-PharosLocation.ps1` verifies `ExpectedPrinters` and **threw** `Printer verification failed` — every install of those apps reported Failed |
| `Pharos WideFormat/Detect-Mck2FloorWideFormat.ps1` | `LIB-Mck2FWideFormat` | `Mck2FWideFormat` | Detection never matched, so Intune reinstalled that app on every check-in |

McKeldin needed two corrections, not one: the queues are `McKeldinBW` /
`McKeldinColor`, not `MckBW` / `MckColor`.

**`Definitions/MarylandRoom/Package.json` is deliberately unchanged** — no
discovery has been run there, so it still reads `LIB-MarylandRoomBW` /
`LIB-MarylandRoomColor` and that package will still fail verification. Run
`Get-PharosPrinterInventory.ps1` on a `LIBRWKMDRP*` PC and correct it.

`PackageSources/` is gitignored and regenerated from `Definitions/` by
`New-PharosIntunePackages.ps1`, so it needs no edit — but rebuild the affected
`.intunewin` packages before reassigning them.
