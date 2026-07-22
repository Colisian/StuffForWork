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

## Pilot checklist (especially for Entra-only devices)

1. Deploy to one test machine; confirm in `%ProgramData%\LibGuestCreation\install.log`
   that all 500 accounts were created.
2. Verify state:
   ```powershell
   Get-LocalUser libguest1
   Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\UserList"
   ```
3. Generate a live credential in SIMS and log on at the machine as that
   `libguestN` account. On Entra-only devices this logon test is the critical
   go/no-go — confirm the credential provider routes the account to Kerberos
   rather than Entra ID.
4. Machine must be able to reach the UMD.EDU KDCs (on-campus network).
