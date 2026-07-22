# LibGuestCreation — Self-Contained Intune Package

Creates local accounts `libguest1`–`libguest500` on library public machines and maps
each one to the Kerberos principal `libguestN@UMD.EDU`. Patrons log on with
credentials issued through SIMS; the machine validates the password directly against
the campus UMD.EDU KDCs (located via DNS). No network share is needed at install
time or at logon time.

Replaces the legacy `libguestcreation.bat` + `kerberos.reg` + `libguest.vbs`, which
pulled files from the decommissioned `\\ussshare.lib.umd.edu` share and used
deprecated VBScript. The old files are preserved in `legacy\` for reference — do not
include that folder when packaging.

## Files

| File | Purpose |
|---|---|
| `Install-LibGuestAccounts.ps1` | Creates realm key, accounts, and UserList mappings. Idempotent. Logs to `%ProgramData%\LibGuestCreation\install.log`. |
| `Uninstall-LibGuestAccounts.ps1` | Removes accounts, profiles, mappings, and realm key. |
| `Detect-LibGuestAccounts.ps1` | Custom detection script — upload in the app's detection rule blade, not part of the payload. |
| `libguest.txt` | Account list, bundled into the package (edit here, then repackage). |

## What the install script does (per machine, once)

1. Creates `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Domains\UMD.EDU`
   (registers the realm; KDCs found via DNS SRV).
2. For each name in `libguest.txt`: creates the local account with a random
   throwaway password (never used — Kerberos handles logon), description
   "Library Local Guest Account", cannot-change-password + never-expires flags,
   and membership in the built-in Users group.
3. Writes `HKLM\...\Lsa\Kerberos\UserList\libguestN@UMD.EDU = libguestN` for each.

## Packaging with IntuneWinAppUtil

From a folder containing IntuneWinAppUtil.exe (Microsoft Win32 Content Prep Tool):

```
IntuneWinAppUtil.exe -c "<this folder>" -s Install-LibGuestAccounts.ps1 -o "<output folder>"
```

Move or exclude `legacy\` and `README.md` first if you want a minimal payload
(only the two .ps1 install/uninstall files and libguest.txt are needed). The `-s`
file is just a required placeholder here — the install is driven by the script, not
by that file — so any bundled file (the install .ps1 or libguest.txt) works.

Both deployment methods below still use this same `.intunewin`, so `libguest.txt`
is always bundled and never needs to be inlined into the script. The scripts detect
which method is in play and locate `libguest.txt` accordingly (`$PSScriptRoot` when
run by command line, current working directory when pasted).

## Intune Win32 app settings

Common to both methods: **Install behavior = System**. Exit codes: 0 = success,
1 = failure (3010 = soft reboot if ever needed).

### Method A — command line calling the packaged script (recommended)

Scripts stay inside the `.intunewin`, so what runs is exactly what you packaged.

- **Install command:**
  `%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-LibGuestAccounts.ps1`
- **Uninstall command:**
  `%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-LibGuestAccounts.ps1`

### Method B — paste the script into Intune's script box

The newer Win32 "PowerShell script installer" flow: paste the *contents* of
`Install-LibGuestAccounts.ps1` / `Uninstall-LibGuestAccounts.ps1` directly into the
install/uninstall script fields. `libguest.txt` still ships in the `.intunewin`, so
the scripts read it from the current working directory (the unpacked package).

- Scripts must stay under the **50 KB** limit (these are well under; do not inline
  the 500-name list — that's what bundling `libguest.txt` avoids).
- The scripts already handle the empty `$PSScriptRoot` this method produces.

### Detection rule (same for both methods)

Nothing lands on disk, so a file/folder rule has nothing to detect. Use either:

- **Registry rule (simplest, no script):**
  - Key: `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\UserList`
  - Value: `libguest500@UMD.EDU`
  - Method: **String equals** `libguest500`
  - (Proves the loop reached the last account.)
- **Custom detection script:** upload `Detect-LibGuestAccounts.ps1` in the
  detection-rule blade (it checks the same sentinel account + mapping).

## Device requirement: hybrid-joined only — Entra-only does NOT work

Tested July 2026. The Kerberos mechanism itself works on any join type (verified:
`runas /user:libguestN@UMD.EDU cmd.exe` with a SIMS password succeeds on an
Entra-only device — realm discovery, KDC reachability, and UserList mapping all
function). But the **lock screen** on an Entra-joined device only accepts two
identity formats: a UPN resolvable in the tenant, or `.\localaccount`. Because the
Entra tenant's verified domain (`umd.edu`) is the same string as the MIT Kerberos
realm (`UMD.EDU`), typing `libguestN@UMD.EDU` is claimed by the cloud provider and
sent to Entra ID (where the account doesn't exist), and the down-level form
`UMD.EDU\libguestN` is rejected outright ("You can not sign in with a user ID in
this format"). There is no supported registry/policy override; this is credential
provider design, not a config error.

Also ruled out: `@ad.umd.edu` as the realm — the libguest principals exist only in
the central UMD.EDU MIT realm (SIMS sets passwords there), so the AD KDC returns
error 1326.

**Consequence:** deploy this package only to Entra **hybrid-joined** (or AD-joined)
devices. For Entra-only public machines, guest access needs a different design
(Shared PC / Assigned Access + a reservation layer such as Pharos SignUp) — the
Kerberos-mapped-local-account model does not apply there.

Realm facts for reference: KDCs are `famine.umd.edu`, `pestilence.umd.edu`,
`war.umd.edu` (port 88; located via `_kerberos._udp/_tcp.umd.edu` DNS SRV records).
The realm name is case-sensitive — users must type `@UMD.EDU` uppercase.

## Pilot checklist

1. Deploy to one test machine; confirm in `%ProgramData%\LibGuestCreation\install.log`
   that all 500 accounts were created.
2. Verify state:
   ```powershell
   Get-LocalUser libguest1
   Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\UserList"
   ```
3. Confirm the device is hybrid/AD-joined (`dsregcmd /status` → `DomainJoined: YES`).
4. Generate a live credential in SIMS and log on at the lock screen as
   `libguestN@UMD.EDU` (uppercase realm).
5. Machine must be able to reach the UMD.EDU KDCs (on-campus network).
