# LibGuest Session Broker — Prototype

> [!info] Version `0.2.0` — session gate, WPF dialog, and live authentication
> This prototype decides **whether** to show the guest sign-in dialog, renders that
> dialog, authenticates the SIMS-issued `libguestN@UMD.EDU` credential with
> `CreateProcessWithLogonW`, and starts an allowlisted application under the mapped
> local security context. See the parent [`../README.md`](../README.md) for the full
> design and security requirements.

> [!warning] This produces an application session, not a Windows desktop logon.
> The broker account still owns the interactive session, window station, and
> desktop. The launched application runs as `libguestN`; everything around it does
> not. That ceiling is inherent to `CreateProcessWithLogonW` and is the reason the
> credential-provider approach still exists as an alternative.

## Files

| File | Purpose |
|---|---|
| `Start-LibGuestSessionBroker.ps1` | Launch gate, WPF dialog host, session lifecycle. Silent in any session that fails the gate. |
| `LibGuestBrokerNative.cs` | `CreateProcessWithLogonW` P/Invoke wrapper, job-object supervision, token readback. |
| `MainWindow.xaml` | UMD-branded sign-in dialog markup. |
| `broker-settings.json` | Nonsecret gate, allowlist, and session configuration. Contains no credentials. |

## What the gate checks

`Test-SharedPcGuestSession` shows the dialog only when every **required** condition
below is true. Each is toggled by `broker-settings.json`:

| Requirement | Config key | Default | Notes |
|---|---|---|---|
| Username matches broker-session pattern | `BrokerSessionAccountPattern` | `^shpc[a-z0-9]+$` | Always required. Matched case-insensitively. Must be `^…$` anchored or the config is rejected. |
| Current identity is a local account | `RequireLocalAccount` | `true` | The current SID appears in `Get-LocalUser`. |
| Shared PC registry configuration present | `RequireSharedPcRegistry` | `true` | Any of the `SharedPC` HKLM keys exist. |
| Member of built-in Guests group | `RequireGuestsGroup` | `false` | Disabled — see hardware findings below. |

Identity facts come from `WindowsIdentity` and the `LocalAccounts` module, **not**
from `%USERNAME%` / `%USERDOMAIN%`. Those variables are writable by the user they
describe, so they are collected for diagnostics only and never decide the gate.

A missing or wrongly typed setting **fails the load** rather than silently dropping
the requirement it controls. `RequireLocalAcount` (typo) is an error, not a
disabled check.

## What happens after a successful sign-in

1. The guest number is parsed to an integer and the principal is rebuilt as
   `libguestN@UMD.EDU`. Raw input never reaches the logon call.
2. `CreateProcessWithLogonW` runs with `LOGON_WITH_PROFILE`, a `NULL` domain (the
   UPN carries the realm), and `CREATE_SUSPENDED`.
3. The suspended process is assigned to a job object carrying
   `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, so every descendant dies when the broker
   closes the job handle or the broker process itself exits.
4. The process token is read back to confirm which identity Windows actually
   produced — this is the proof that the Kerberos `UserList` mapping resolved.
5. What happens next depends on the application's `Mode`.

| Mode | Behavior | Trade |
|---|---|---|
| `IdentityTest` | Reads the token, tears the process down while still suspended, stays on the dialog | Nothing executes as the guest. Diagnostics only. |
| `LaunchAndExit` | Launches the application, then the broker closes and exits | **Current default for Edge.** The application outlives the broker. No session timer, no cleanup, no return to the dialog. |
| `Session` | Launches, hides the dialog, supervises via a job object, returns to the dialog when the application exits | Time limit and guaranteed cleanup, but the application dies with the broker. |

`LaunchAndExit` skips the job object entirely and releases the process handles once
the application is running. That is what lets the broker exit without
`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` taking the application with it — the two
behaviors are inseparable, so choosing one gives up the other.

### Password handling

The plaintext password exists only in an unmanaged buffer from
`Marshal.SecureStringToCoTaskMemUnicode`, released by
`Marshal.ZeroFreeCoTaskMemUnicode` in a `finally` that runs immediately after the
API returns. It is never copied into a managed `String`, never placed on a command
line, and never logged. `PasswordBox.SecurePassword` returns a fresh copy on every
read, so the broker disposes its copy and clears the control.

### Errors the patron sees

Every credential-related Win32 code (`1326`, `1327`, `1330`, `1331`, `1909`,
`1907`, …) produces one identical message, so the dialog cannot be used to probe
whether an account exists, is locked, or is disabled. The specific code goes to the
log. Infrastructure faults (KDC unreachable, Secondary Logon disabled, missing
binary) produce a distinct "see the service desk" message.

## Configuration reference

| Key | Purpose |
|---|---|
| `AllowDevelopmentOverrides` | Must be `true` before `-ForceGuestUi` does anything. Ships `false`. |
| `GuestAccountPrefix` | `libguest`. Drives both input parsing and principal construction. |
| `MinimumGuestNumber` / `MaximumGuestNumber` | `1`–`500`. Also sets the textbox `MaxLength` and tooltip at load time. |
| `Realm` | `UMD.EDU`. |
| `LogGuestPrincipal` | `false`. When false the log records `(redacted)` instead of `libguestN@UMD.EDU`. See the retention note in the parent README. |
| `SessionTimeoutMinutes` | `60`. Applies to `Mode: Session` only. Ignored by `LaunchAndExit`, which has no supervising process. |
| `AllowedApplicationRoots` | Executables must resolve under one of these roots. Paths are canonicalized first, so `%SystemRoot%\..\Users\x.exe` cannot pass. |
| `Applications` | The allowlist. Each entry needs `Id`, `DisplayName`, `Path`, `Mode`. |
| `DefaultApplicationId` | Which allowlist entry launches when `-ApplicationId` is not supplied. |

## Status — accomplished

- [x] Launch gate evaluates the current session before any window loads.
- [x] Gate keys on `WindowsIdentity` + `Get-LocalUser`, not spoofable environment variables.
- [x] Configuration fails closed: missing keys, wrong types, unanchored or invalid
      regex, bad `Mode`, and out-of-range numbers all reject at load.
- [x] `-ProbeOnly` emits session markers, launch prerequisites, and the resolved
      application as JSON.
- [x] `-ForceGuestUi` is inert unless `AllowDevelopmentOverrides` is `true`.
- [x] WPF dialog renders with UMD branding through all visual states (a custom
      `ControlTemplate` keeps the button red on hover/press instead of reverting to
      the Aero highlight); `Enter` submits, initial focus lands on the guest-number
      field, validation errors render red and reset correctly.
- [x] `CreateProcessWithLogonW` authentication with unmanaged-only password
      lifetime and immediate zeroing.
- [x] Job-object supervision with kill-on-close, plus token readback proving the
      mapped identity.
- [x] Session monitor on a dispatcher timer (a blocking wait would freeze the
      message pump), with a configurable time limit.
- [x] Generic credential errors; sanitized Win32 codes to
      `C:\ProgramData\LibGuestSessionBroker\broker.log`.
- [x] Secondary Logon and LocalSystem preflight checks with actionable failures.

### Validated on hardware — `LIBR8ZCBLK4` (2026-07-26)

Configured Entra-only Shared PC public device.

**Phase 1 authentication — PASSED.** Run via
[`../Tests/Test-BrokerLaunch.ps1`](../Tests/Test-BrokerLaunch.ps1) as `AD\cmcleod1`
from an elevated console, which bypasses the session gate.

| Check | Result |
|---|---|
| C# compiles under Windows PowerShell `5.1.26100.8655` | Compiled successfully (CodeDOM, not Roslyn) |
| Secondary Logon service | `Manual` / `Running` |
| Local account: `libtest` + `-Domain LIBR8ZCBLK4` | `TokenAccount: LIBR8ZCBLK4\libtest` |
| **SIMS credential: `libguest115@UMD.EDU`** | **`TokenAccount: LIBR8ZCBLK4\libguest115`, SID `…-1115`** |
| `-Mode Session` with `notepad.exe` | Process resumed and ran as the target identity |
| **Job cleanup: broker killed while child running** | **Child terminated with the broker** |

**End-to-end in a real Guest session (2026-07-27, at the console).** The full broker
— gate, dialog, and authentication — run as the dynamically created `shpc` account:

| Check | Result |
|---|---|
| Gate passed; dialog displayed | As expected |
| Authentication with `libguest115` + SIMS password | Succeeded, mapped to the local account |
| Wrong password | Rejected with the generic failure message |
| Out-of-range guest numbers | Rejected by input validation |

The prototype is functionally complete for Phase 1. Everything remaining is
containment, not authentication.

The SIMS row is the Phase 1 go/no-go. It confirms three things at once: the UMD.EDU
KDC accepted the MIT Kerberos principal from an Entra-only device, the
`Lsa\Kerberos\UserList` registry mapping resolved it, and the resulting token is the
**local** `libguest115` matching the number supplied — not a network identity and
not a different account.

Unlike the rotating `shpc` broker account, the `libguestN` SIDs are stable and
their RIDs track the account number (`libguest115` → RID `1115`), consistent with
the accounts the existing LibGuest installer pre-creates.

The local-account row is what proved the native layer independently of Kerberos:
P/Invoke signatures, `SecureString` marshalling, `CREATE_SUSPENDED`, job assignment,
and the token readback all work. A corrupted password buffer would have returned
`1326` exactly like a wrong password, so this row is what rules that out.

The job-cleanup row settles the process-supervision go/no-go from the parent
README: killing the broker terminated the child process with it, confirming
`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` holds even when the broker dies without
running any cleanup code of its own.

> [!note] What this does **not** cover.
> Everything above ran as an elevated domain admin, outside the gate and outside
> the UI. The gate, the dialog, the session monitor, and standard-user file
> permissions are still unvalidated on `0.2.0`.

**Gate validation (version `0.1.1`, gate only):**

| Check | Result |
|---|---|
| `-ProbeOnly` in a Guest session | `IsGuestSession: true`, `FailedRequirements: []` |
| Run without `-ProbeOnly` in a Guest session | Gate passed; dialog displayed as expected |

**Findings that shaped the current config:**

- The broker-session account is `shpc` + a **random alphanumeric** suffix
  (e.g. `shpctac0ffef`, `shpctac0fff1`), **not** `shpc` + digits. The original
  `^shpc\d+$` pattern failed; corrected to `^shpc[a-z0-9]+$`.
- The account is a member of built-in **Users**, not **Guests**
  (`IsGuestsGroupMember: false`). `RequireGuestsGroup` was therefore disabled;
  leaving it on would permanently suppress the UI on this build.
- The disposable account name and SID **rotate every session** (RID `1502` →
  `1504` across two logons), confirming the gate must key on the name *shape* and
  the SharedPC registry markers, never a specific account name or SID.

## Status — remaining

- [ ] **Test the fullscreen dialog and lockdown policy in a Guest session.** Run
      [`../Containment/Set-GuestSessionLockdown.ps1`](../Containment/Set-GuestSessionLockdown.ps1),
      sign out, start a new Guest session, and confirm Win+D, Win+E, Win+R,
      Ctrl+Shift+Esc and the taskbar right-click are all dead.
- [ ] **Multi-process cleanup.** Job teardown is proven for a single child
      (`notepad.exe`). A browser spawns a process tree and may try to break away
      from the job; re-verify with Edge during Phase 2.
- [ ] **Negative-path probe:** sign in through the **Domain/Entra** option and run
      `-ProbeOnly`; confirm `IsGuestSession: false`.
- [ ] **Re-probe on each new Windows build** before trusting the gate; the `shpc`
      naming and group membership are undocumented and may change.
- [ ] **Phase 2 — one allowlisted GUI app:** switch `DefaultApplicationId` to
      `Edge` and test profile, downloads, printing, clipboard, child processes,
      updates, and forced termination.
- [ ] **Session cleanup:** the job object terminates processes but nothing yet
      clears browser data, downloads, or print artifacts.
- [ ] **Phase 3 — restricted broker shell:** Assigned Access / custom shell,
      machine-wide silent auto-start entry, Intune packaging
      (`Install`/`Uninstall`/`Detect` wrappers).
- [ ] **Replace `Add-Type` with a signed compiled binary.** `Add-Type` produces a
      dynamically compiled assembly, which is exactly what the planned WDAC / App
      Control policy blocks. The production form is the C#/.NET WPF executable
      described in the parent README.

## Test harnesses

Both live in [`../Tests`](../Tests/), deliberately outside `Prototype` so they are
not copied to devices with the package.

| Script | Platform | Answers |
|---|---|---|
| `Test-BrokerConfiguration.ps1` | any (pwsh) | Does the config fail closed, and does the gate decide correctly? |
| `Test-BrokerLaunch.ps1` | Windows | Does the native launch path work, and does Windows accept this credential? |

`Test-BrokerLaunch.ps1` takes a `-Domain`, so the whole
`CreateProcessWithLogonW` path can be exercised against a throwaway **local**
account on an ordinary Windows VM — no Shared PC device and no live SIMS password
required. Run it there before spending a trip to the hardware.

## Deploying to a test machine

Stage to a machine-wide location, strip mark-of-the-web (OneDrive-synced files
carry it), and **set the ACL explicitly**:

```powershell
$dest = 'C:\ProgramData\LibGuestSessionBroker\Prototype'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item '<source>\Prototype\*' $dest -Recurse -Force
Get-ChildItem $dest -Recurse | Unblock-File
```

```powershell
# Break inheritance so the guest account cannot modify the gate config or the
# script. Without this, whichever account creates C:\ProgramData\LibGuestSessionBroker
# first becomes CREATOR OWNER of it.
$root = 'C:\ProgramData\LibGuestSessionBroker'
$acl = Get-Acl $root
$acl.SetAccessRuleProtection($true, $false)
$acl.Access | ForEach-Object { $null = $acl.RemoveAccessRule($_) }
foreach ($principal in 'BUILTIN\Administrators', 'NT AUTHORITY\SYSTEM') {
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $principal, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
}
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
    'BUILTIN\Users', 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
Set-Acl -Path $root -AclObject $acl
```

> [!note] The broker logs best-effort.
> With the ACL above, a guest session cannot write `broker.log`. That is
> deliberate — logging never blocks the broker. To collect logs from guest
> sessions, grant `Users` **write** on `broker.log` alone (not the directory), or
> move logging to the Windows Event Log in the production build.

## Phase 1 test procedure

Run these in order on `LIBR8ZCBLK4`. Steps 1–2 need no credential.

**1. Probe from a Guest session.** Confirms the gate, the Secondary Logon service,
and the resolved application in one shot:

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile `
  -File 'C:\ProgramData\LibGuestSessionBroker\Prototype\Start-LibGuestSessionBroker.ps1' -ProbeOnly
```

Expect `GuestDecision.IsGuestSession: true`, `Prerequisites.SecondaryLogonUsable:
true`, `Prerequisites.IsSystemAccount: false`, and a populated `Application` block
with `ApplicationError: null`.

> If `SecondaryLogonUsable` is `false`, stop. `CreateProcessWithLogonW` cannot work
> without that service, and several hardening baselines disable it.

**2. Probe from a Domain/Entra session.** Expect `IsGuestSession: false` with
`LocalAccount` and `BrokerSessionAccountPattern` in `FailedRequirements`.

**3. Identity test with a live SIMS credential.** `DefaultApplicationId` ships as
`IdentityTest`, so this authenticates and reads the token back without executing
anything as the guest:

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile `
  -File 'C:\ProgramData\LibGuestSessionBroker\Prototype\Start-LibGuestSessionBroker.ps1'
```

Success shows: `Authentication succeeded. Windows mapped the credential to
LIBR8ZCBLK4\libguestN (SID S-1-5-21-…-1xxx).`

**This is the Phase 1 go/no-go.** The resolved account must be the local
`libguestN` matching the number entered. If it resolves to anything else, the
`UserList` mapping is wrong — stop and fix that before Phase 2.

**4. Wrong-password check.** Expect the generic *"Sign-in failed. Check the guest
number and password"* message, and a `Win32Error=1326 Category=Credential` line in
the log. The dialog must not distinguish a bad password from a nonexistent account.

**5. Real application (Phase 2 entry).** Set `DefaultApplicationId` to `Edge` in
`broker-settings.json`, or pass `-ApplicationId Edge`:

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile `
  -File 'C:\ProgramData\LibGuestSessionBroker\Prototype\Start-LibGuestSessionBroker.ps1' -ApplicationId Edge
```

The dialog hides, Edge starts as `libguestN`, and closing Edge returns the dialog.
Confirm with Task Manager that `msedge.exe` runs as `libguestN` while the broker's
own `powershell.exe` still runs as `shpc…`. That split is the mixed-identity
desktop the parent README describes.

**6. Cleanup check.** With Edge running, kill the broker `powershell.exe` from
Task Manager. Every `msedge.exe` must die with it — that is
`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` doing its job. If any survive, process
supervision is broken and Phase 3 cannot proceed.

## Previewing the dialog on a dev machine

Set `AllowDevelopmentOverrides` to `true` in a **local copy** of
`broker-settings.json`, then:

```powershell
.\Start-LibGuestSessionBroker.ps1 -ForceGuestUi
```

> [!warning] Never ship a package with `AllowDevelopmentOverrides: true`.
> Once authentication is wired, a flag that renders a UMD-branded credential prompt
> outside the gate is a ready-made phishing surface on a machine-wide auto-start
> entry. The flag ships `false` and `-ForceGuestUi` is logged and ignored without
> it.

## Making it start by itself

Nothing auto-starts the broker until this is run. `broker-settings.json` and the
`BrokerSessionAccountPattern` decide **whether the dialog appears** once the broker
is already running; they do not cause it to run.

Run all three, in order, elevated, after staging the `Prototype` folder:

```powershell
cd C:\BrokerTest\Containment
.\Set-GuestSessionLockdown.ps1        # policy for new profiles
.\Install-BrokerAutoStart.ps1         # All Users Startup shortcut
```

Then sign out and start a new Guest session. The broker starts for **every** logon;
non-guest sessions fail the gate and exit silently without a window.

`-Remove` on either script reverts it.

> [!note] There is a visible gap at logon.
> Startup items run after the shell has painted, so the desktop is briefly visible
> before the broker covers it. That gap is inherent to this approach and is one of
> the things Shell Launcher would remove. Accepted under the accountability-gate
> model — see "Containment model" in [`../README.md`](../README.md).
