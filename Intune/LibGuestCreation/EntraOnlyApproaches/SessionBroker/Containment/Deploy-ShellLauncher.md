# Phase 3 — Shell Launcher deployment

> [!info] What this delivers
> The patron signs in to nothing. The device boots straight into the broker
> dialog, and there is no desktop behind it — `explorer.exe` never starts. This is
> the structural version of "cannot access anything until authenticated," as
> opposed to a fullscreen window covering a desktop that still exists.

Companion file: [`ShellLauncher-LibGuest.xml`](./ShellLauncher-LibGuest.xml)

## Two findings that changed the plan

**1. You do not need a `libbroker` account.**

The earlier plan was a hand-made local account plus auto-logon, which meant storing
a credential in `AutoAdminLogon`/`DefaultPassword` or an LSA secret. Shell Launcher
has `<AutoLogonAccount/>`: it creates and manages its own local standard account and
signs it in after restart. **Windows owns that credential.** Nothing is stored by us,
and there is no broker-account password to rotate, escrow, or leak.

Microsoft documents the managed account as a local standard user named `Kiosk`.

**2. Shell Launcher ships through the AssignedAccess CSP, and enables itself.**

The OMA-URI is `./Vendor/MSFT/AssignedAccess/ShellLauncher`, not a `ShellLauncher`
CSP path. Deploying it this way automatically enables the Shell Launcher optional
feature on a supported device, so the DISM / `Enable-WindowsOptionalFeature` step
that appears in most write-ups is unnecessary for the Intune path.

## Prerequisite: check the edition first

Shell Launcher requires **Enterprise, Enterprise LTSC, Education, or IoT
Enterprise**. Pro and Home cannot run it, and the policy will fail on those devices.

```powershell
Get-ComputerInfo -Property WindowsProductName, WindowsEditionId, Osarchitecture
```

Check `LIBR8ZCBLK4` and a representative sample of the lab fleet before building the
profile. If any lab machines are Pro, this approach does not cover them and the
licensing question needs answering before further work.

## Intune deployment

**Devices → Configuration → Create → New policy**
Platform **Windows 10 and later**, profile type **Templates → Custom**.

| Field | Value |
|---|---|
| Name | `Windows – LibGuest Shell Launcher` |
| OMA-URI | `./Vendor/MSFT/AssignedAccess/ShellLauncher` |
| Data type | `String` |
| Value | entire contents of `ShellLauncher-LibGuest.xml` |

Assign to a **device group** containing only the pilot machine at first. Never
assign this to a broad group before the recovery path below has been rehearsed.

> [!warning] Assign to devices, not users.
> The patron identity is a local `libguestN` account with no Entra presence. A
> user-assigned policy has nothing to attach to. This is the same constraint that
> forces the Edge policy to HKLM.

## The exit-code contract — read before changing the XML

Shell Launcher decides what to do when the shell process exits. Get this wrong and
you produce either a black screen or a boot loop.

| Exit code | Action | Why |
|---|---|---|
| `0` | `RestartShell` | Normal end of session; sign-in dialog returns |
| `1` | `DoNothing` | Unrecoverable failure — see below |
| `2` | `RestartDevice` | Staff-requested restart |
| anything else | `RestartShell` | Default |

**Why `1` maps to `DoNothing`.** If the broker fails at startup — bad config,
missing file, denied ACL — then `RestartShell` spins on it forever and
`RestartDevice` turns that spin into a boot loop that requires physical media to
break. `DoNothing` leaves a blank screen, which looks worse but is recoverable:
`Ctrl+Alt+Del` still offers **Sign out**, and staff can then sign in as an
administrator.

Microsoft's own documentation calls this out: a shell that exits automatically
"can lead to an infinite cycle of exiting and restarting."

## Broker code changes this forces

The current prototype was written to run *inside* a session. As a shell, three
behaviors are now wrong:

- [ ] **Silent exit on gate failure.** `Start-LibGuestSessionBroker.ps1` returns
      `0` when the gate does not pass. As a shell that means `RestartShell` →
      gate fails → exit → **infinite loop**. Under Shell Launcher a gate failure
      must exit `1`.
- [ ] **The gate pattern no longer matches.** `^shpc[a-z0-9]+$` will not match the
      Shell Launcher managed account. Verify the real name on the device and
      update `BrokerSessionAccountPattern` accordingly.
- [ ] **The window needs a full-screen backdrop.** `AllAppsFullScreen` is `false`
      so Edge can manage its own kiosk presentation, which means the broker's
      520×560 dialog would float on a black screen with no desktop behind it. The
      window should paint full screen with the existing card centered.

Also revisit, once the managed account is confirmed:

| Setting | Now | Under Shell Launcher |
|---|---|---|
| `BrokerSessionAccountPattern` | `^shpc[a-z0-9]+$` | `^Kiosk$` — **verify first** |
| `RequireSharedPcRegistry` | `true` | Depends on whether Shared PC mode stays |
| `RequireLocalAccount` | `true` | Keep `true` |

Verify the account name on the device after the policy applies:

```powershell
Get-LocalUser | Where-Object Enabled | Select-Object Name, SID, Description
```

> [!warning] Do not assume the name is `Kiosk`.
> The `shpc` account was assumed to be `shpc` + digits and turned out to be
> `shpc` + random alphanumeric; `RequireGuestsGroup` was assumed safe and turned
> out to suppress the UI entirely. Both cost a hardware trip. Read the name off
> the device before writing it into config.

## Interaction with Shared PC mode

`LIBR8ZCBLK4` currently runs Shared PC mode, which is what produces the **Guest**
button and the rotating `shpc` accounts. With `<AutoLogonAccount/>` the device
signs itself in before any logon screen appears, so that flow is bypassed.

Unresolved, and worth settling before the pilot:

- Does Shared PC mode's account manager interfere with the Shell Launcher managed
  account, or try to delete it?
- Shared PC mode also provides disk-space cleanup, sleep and wake policy, and
  account deletion. Dropping it means owning those separately.
- If Shared PC mode stays, `RequireSharedPcRegistry` can stay `true` and provides
  a little defense in depth. If it goes, set it `false` or the gate will never pass.

Recommendation: keep Shared PC mode enabled for the first pilot and change one
thing at a time.

## Recovery — rehearse this before assigning the policy

Shell Launcher takes effect at next sign-in, and a broken broker means a device
with no usable interface. Know all three routes out before you need them:

1. **Sign out to another account.** `Ctrl+Alt+Del` → **Sign out**, then sign in as
   an administrator. The `DefaultProfile` in the XML gives admins `explorer.exe`,
   so this is the normal recovery path and it should work in every failure mode
   except a broken `DefaultProfile`.
2. **Unassign the Intune policy.** Removes the configuration on next sync. Slow,
   and requires the device to still be checking in.
3. **Safe Mode.** Shell Launcher does not apply, so you get a normal desktop.

Test route 1 on the pilot device *immediately* after the policy first applies,
before doing anything else.

## Deployment order

Do not combine these. Each step should be separately reversible.

1. Confirm the Windows edition supports Shell Launcher.
2. Finish [Edge containment testing](./EdgeEscapeTests.md). **If Edge cannot be
   contained, stop — Shell Launcher does not fix an escapable browser.**
3. Build the broker as a signed executable. The PowerShell prototype cannot be a
   shell target, and dynamic `Add-Type` compilation is what WDAC blocks anyway.
4. Fix the three broker behaviors listed above.
5. Apply Shell Launcher to one pilot device. Verify the managed account name.
   Rehearse recovery route 1.
6. Update `broker-settings.json` for the new account name.
7. Only then: WDAC / App Control allowlist.

Step 7 is last but it is the step that makes the whole thing actually contained.
Policy and shell replacement reduce the surface; execution control is what makes an
escape not matter.

## Sources

- [Configure Shell Launcher](https://learn.microsoft.com/en-us/windows/configuration/shell-launcher/configure)
- [Create a Shell Launcher configuration file](https://learn.microsoft.com/en-us/windows/configuration/shell-launcher/configuration-file)
- [AssignedAccess CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/assignedaccess-csp)
