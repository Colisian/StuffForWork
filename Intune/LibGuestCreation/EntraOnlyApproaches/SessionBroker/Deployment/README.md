# Intune Win32 deployment — LibGuest session broker

> [!info] Version `0.3.1`
> One Win32 app performs the entire device configuration: stages the broker,
> locks down the install root, applies guest session and Edge policy, registers
> auto-start, and creates the session accountability CSV.

## Layout

```text
Deployment/
├── Detect-LibGuestSessionBroker.ps1     uploaded to Intune, NOT packaged
├── README.md                            this file
└── Package/                             <-- point IntuneWinAppUtil here
    ├── Install-LibGuestSessionBroker.ps1
    ├── Uninstall-LibGuestSessionBroker.ps1
    ├── Prototype/
    │   ├── Start-LibGuestSessionBroker.ps1
    │   ├── LibGuestBrokerNative.cs
    │   ├── MainWindow.xaml
    │   └── broker-settings.json
    └── Containment/
        ├── Set-GuestSessionLockdown.ps1
        ├── Set-EdgeContainmentPolicy.ps1
        └── Install-BrokerAutoStart.ps1
```

`Package/` holds the **only** copies of these files — they are not duplicated
elsewhere in the repository, so there is no second copy to forget to update.
Everything in `Package/` belongs in the `.intunewin`; nothing else does.

## What the app does to a device

| Step | Result |
|---|---|
| 1 | Broker files staged to `C:\ProgramData\LibGuestSessionBroker\Prototype` |
| 2 | Install root ACL: Administrators/SYSTEM full, Users read-and-execute, `broker.log` writable, `sessions.csv` **append-only** for Users |
| 3 | Guest session policy written into `C:\Users\Default\NTUSER.DAT` |
| 4 | Machine-wide Edge policy under `HKLM\SOFTWARE\Policies\Microsoft\Edge` |
| 5 | Startup shortcut in the All Users Startup folder |
| 6 | Detection sentinel at `HKLM\SOFTWARE\UMDLibraries\LibGuestSessionBroker` |

Step 6 is written **last**, so it exists only if everything above succeeded.

Before touching anything, install refuses to run if `broker-settings.json` has
`AllowDevelopmentOverrides` set to `true` — a package that can render a credential
prompt outside the session gate must never reach a fleet device.

## Build the package

```powershell
IntuneWinAppUtil.exe -c "<repo>\...\SessionBroker\Deployment\Package" `
                     -s "<repo>\...\SessionBroker\Deployment\Package\Install-LibGuestSessionBroker.ps1" `
                     -o "<output folder>"
```

`-s` is required even though nothing about this install is setup-file driven. It is
a placeholder; the install command or script is what actually runs.

Before building, confirm the shipping configuration is what you intend:

```powershell
Get-Content .\Package\Prototype\broker-settings.json |
    Select-String 'DefaultApplicationId|AllowDevelopmentOverrides|"Mode"'
```

Expect `DefaultApplicationId` = `Edge`, `AllowDevelopmentOverrides` = `false`, and
the Edge entry in `LaunchAndExit` mode.

## Create the app in Intune

**Apps → Windows → Add → Windows app (Win32)**, upload the `.intunewin`.

### Program — either method works

Both scripts are written to run identically whether invoked from a command line or
pasted into Intune's PowerShell script boxes. They locate their bundled companion
files through the working directory, not `$PSScriptRoot`, and they never depend on
`$PSCommandPath`.

**Option A — command line**

| Field | Value |
|---|---|
| Install command | `powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-LibGuestSessionBroker.ps1` |
| Uninstall command | `powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-LibGuestSessionBroker.ps1` |

**Option B — PowerShell script content**

Paste the full contents of `Install-LibGuestSessionBroker.ps1` into the install
script box and `Uninstall-LibGuestSessionBroker.ps1` into the uninstall box. Both
are comfortably under the 50 KB limit (about 14 KB and 9 KB).

You still upload the same `.intunewin`. The pasted script runs with the unpacked
package as its working directory, which is how it finds `Prototype\` and
`Containment\`. **Pasting the scripts does not remove the need for the package** —
the broker files themselves are only in the `.intunewin`.

> [!important] If you paste, the pasted copy is what runs.
> The scripts inside the `.intunewin` become dead weight, and the two can silently
> diverge. Re-paste whenever you rebuild the package, or use Option A so the script
> is versioned inside the package it ships with.

**Both options:**

| Field | Value |
|---|---|
| Install behavior | **System** |
| Device restart behavior | No specific action |

### Requirements

| Field | Value |
|---|---|
| Operating system architecture | x64 |
| Minimum operating system | Windows 10 1809 or later |

### Detection rules

Rules format: **Use a custom detection script**. Upload
`Detect-LibGuestSessionBroker.ps1` (from `Deployment/`, not from the package).

| Field | Value |
|---|---|
| Run script as 32-bit process on 64-bit clients | **No** |
| Enforce script signature check | No |

### Assignments

Assign to a **device** group containing the public workstations. Never a user
group: the patron identity is a local `libguestN` account with no Entra presence,
so a user assignment has nothing to attach to.

Start with one pilot device.

## Registry bitness

All three scripts read and write the sentinel through an explicit **64-bit registry
view** (`RegistryView::Registry64`) rather than trusting the host process bitness.

The Intune Management Extension may invoke scripts in 32-bit PowerShell, where
`HKLM\SOFTWARE` is redirected to `WOW6432Node`. Without the explicit view, install
would write the sentinel somewhere detection never looks, and every device would
report as not installed and reinstall on every check-in.

An explicit view is used instead of relaunching through `SysNative` precisely
because a relaunch needs `$PSCommandPath`, which is empty when a script is pasted
into Intune. Setting the detection script's 32-bit toggle to **No** is still
correct — the two protections are independent.

`HKLM\SOFTWARE\Policies` is a shared key and is not redirected, so the Edge policy
is unaffected either way.

## Detection design

Detection keys on a registry sentinel, not a file rule. Most of what this app does
is not a file — Default-hive policy, Edge policy, an ACL, a shortcut. A file rule
would report the app installed as soon as the copy finished, even if every
configuration step afterwards failed.

The script also confirms the broker script and the startup shortcut still exist, so
a device where something stripped part of the configuration is re-mediated rather
than reported healthy.

> [!important] Version bumps
> `$productVersion` in the install script and `$expectedVersion` in the detection
> script are separate constants — a detection script runs standalone and cannot
> read the package. **Bump both together.** Bumping only install means no device
> ever detects as installed; bumping only detection triggers a fleet-wide
> reinstall.

## Verify on the pilot device

```powershell
# 1. Sentinel written, in the 64-bit view
Get-ItemProperty 'HKLM:\SOFTWARE\UMDLibraries\LibGuestSessionBroker'

# 2. Detection agrees (should print "... detected")
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Detect-LibGuestSessionBroker.ps1

# 3. Files staged and locked down
Get-ChildItem 'C:\ProgramData\LibGuestSessionBroker\Prototype'
(Get-Acl 'C:\ProgramData\LibGuestSessionBroker').Access |
    Select-Object IdentityReference, FileSystemRights

# 4. Auto-start registered
Test-Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\UMD Libraries Guest Access.lnk"

# 5. Edge policy in force
Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
```

Then sign out, start a **new** Guest session, and confirm the dialog appears,
`libguestN` + SIMS password launches Edge, and Win+D / Ctrl+Shift+Esc are dead.

Install log: `C:\ProgramData\LibGuestSessionBroker\install.log`
Intune log: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log`

## Session accountability log

`C:\ProgramData\LibGuestSessionBroker\sessions.csv` records who authenticated and
when:

| Column | Content |
|---|---|
| `Timestamp` | ISO 8601, local time with offset |
| `Event` | `SignIn`, `SignInFailed`, or `SessionEnd` |
| `GuestAccount` | `libguestN` — recorded here by design, unlike the redacted `broker.log` |
| `SessionId` | GUID correlating a `SignIn` row with its `SessionEnd` row |
| `DurationMinutes` | On `SessionEnd` rows |
| `Detail` | Token account on sign-in; Win32 code and category on failure |

The broker writes `SignIn`/`SignInFailed` at authentication. In `LaunchAndExit`
mode a hidden watcher (`Watch-GuestSession.ps1`, running as the same guest) waits
for the launched process to exit and appends `SessionEnd` with the duration.

**Users get `AppendData` only** — a guest session can add rows but cannot rewrite
or delete history. True read-only is impossible because the broker itself runs as
the guest and is the only process that observes the events. Administrators have
full control.

Known limits:

- If the patron signs out of Windows while the application is still open, the
  watcher dies with the session and the `SignIn` row has no matching `SessionEnd`.
- Duration measures the **launched process**. If Edge hands off to an existing
  instance (should not happen in a fresh guest session), the row closes early.
- This file names patron accounts with timestamps — it is a patron activity
  record. Apply whatever retention policy governs such records; uninstall deletes
  it unless run with `-KeepLogs`.

Quick queries:

```powershell
Import-Csv 'C:\ProgramData\LibGuestSessionBroker\sessions.csv' |
    Where-Object Event -eq 'SignIn' | Select-Object Timestamp, GuestAccount

# Sessions with durations
Import-Csv 'C:\ProgramData\LibGuestSessionBroker\sessions.csv' |
    Where-Object Event -eq 'SessionEnd' |
    Select-Object Timestamp, GuestAccount, DurationMinutes
```

## Known behaviors

- **Existing guest profiles keep their old policy.** Only profiles created after
  install inherit the Default-hive settings. Shared PC rotates guest accounts, so
  this resolves at the next sign-in — but a device left signed in is unchanged
  until it is not.
- **Edge policy is machine-wide**, so it also applies to administrators browsing on
  that device. Accepted on a dedicated public workstation; pass `-SkipEdgePolicy`
  to the install script if Edge is managed by a separate Settings Catalog profile.
- **Uninstall exits 0 even when steps fail**, by design — a partially installed
  device must still be removable. It exits 1 only if the sentinel survives, since
  that would leave Intune believing the app is installed. Check `uninstall.log` or
  the Intune log for warnings.
- **No reboot is required.** The install never returns 3010.

## Rolling back

Uninstall through Intune, or by hand from the extracted package folder:

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-LibGuestSessionBroker.ps1
```

Run it from the package folder so the bundled `Containment` scripts are available
to reverse their own policy. Without them, uninstall still removes the shortcut,
the Edge policy key, the sentinel, and the files — but it cannot cleanly reverse
the Default-hive policy, and logs a warning saying so.

Guest sessions started before the uninstall keep their restrictions until sign-out.
