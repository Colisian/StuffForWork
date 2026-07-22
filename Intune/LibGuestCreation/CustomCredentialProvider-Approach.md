# Custom Credential Provider for LibGuest on Entra-Only Devices

**Status:** Concept / not yet built. Reference doc for a future attempt.
**Last updated:** 2026-07-22
**Author context:** UMD Libraries, Lead IT Engineer. Fleet is Intune-managed
(Win32 apps, no GPO). Public/lab machines.

This document is written to be self-contained: hand it to an LLM (or read it
yourself) with no prior conversation and it should convey the full problem, why the
simple fixes don't work, and how a custom credential provider would solve it.

---

## 1. The problem I'm trying to solve

Library public machines let walk-up patrons log in with temporary **guest accounts**
(`libguest1`–`libguest500`). The way this works today:

- Each machine has 500 **local Windows accounts** named `libguestN`.
- The registry maps each local account to a **Kerberos principal** in the campus
  MIT Kerberos realm `UMD.EDU`:
  - `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Domains\UMD.EDU` — declares
    the realm (KDCs found via DNS SRV).
  - `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\UserList\libguestN@UMD.EDU`
    = `libguestN` — maps the principal to the local account.
- Front-desk staff issue a patron a username + password through **SIMS** (Special
  Identity Management System). SIMS sets the password on the central
  `libguestN@UMD.EDU` Kerberos principal.
- At the lock screen the patron types `libguestN@UMD.EDU` + password. Windows
  validates the password against the `UMD.EDU` KDC and logs them into the local
  `libguestN` profile. The local account's own SAM password is never used for this.

**This works on AD-joined / Entra-hybrid-joined machines. It does NOT work on
Entra-only (Azure AD Joined, not domain-joined) machines.** I want guest logon to
work on Entra-only devices, ideally without changing SIMS or the front-desk
workflow.

### Realm reference facts

- Realm name: `UMD.EDU` (case-sensitive — must be typed uppercase).
- KDCs: `famine.umd.edu`, `pestilence.umd.edu`, `war.umd.edu` on TCP/UDP **88**.
- Located via DNS SRV: `_kerberos._udp.umd.edu`, `_kerberos._tcp.umd.edu`.
- TXT `_kerberos.umd.edu` = `UMD.EDU`.

---

## 2. Why the simple fixes don't work (already tested, July 2026)

| Test | Result | What it proves |
|---|---|---|
| `runas /user:libguestN@UMD.EDU cmd.exe` on an Entra-only box (SIMS password) | **Works** | The whole Kerberos stack — realm discovery, KDC reachability, UserList mapping — functions on Entra-only hardware. LSA does the right thing. |
| Lock screen `libguestN@UMD.EDU` on Entra-only | **Fails** — routed to Entra ID | The cloud credential provider (CloudAP) claims it. |
| Lock screen `UMD.EDU\libguestN` (down-level) | **Fails** — "You can not sign in with a user ID in this format. Try using your email address instead" | The Entra-joined lock screen rejects `DOMAIN\user` format outright. |
| `runas /user:libguestN@ad.umd.edu` | **Fails — error 1326** | The guest principals exist only in the central `UMD.EDU` MIT realm, not the AD forest. Can't dodge to the AD realm. |

### Root cause

The Entra tenant's **verified domain is `umd.edu`** — the *same string* as the MIT
Kerberos realm `UMD.EDU`. On an Entra-joined device, when a user types
`something@umd.edu` at the lock screen, Windows' home-realm discovery matches the
tenant domain and hands the credential to **CloudAP → Entra ID**, where `libguestN`
doesn't exist. The Kerberos SSP (which would happily handle it) never gets a look.

On AD-joined machines there's no collision: the machine's domain is `ad.umd.edu`
(≠ `UMD.EDU`) and there's no cloud provider competing, so the Kerberos SSP wins.

**Key insight:** the Entra-joined lock screen only accepts two identity formats — a
UPN it can resolve in the tenant, or `.\localaccount`. There is **no typed format**
that reaches the MIT-Kerberos path, and no registry/policy override. This is
credential-provider *design*, not a misconfiguration. `runas` works only because it
bypasses the lock-screen UI and calls `LsaLogonUser` directly.

### Options considered

1. **Hybrid-join the machines** — reliable, no custom code, fully supported. The
   recommended answer unless the fleet must be Entra-only. (Management stays
   Intune-native; hybrid join is an identity-plane choice, not GPO.)
2. **Entra-native redesign** — Shared PC / Assigned Access kiosk + a reservation
   layer (e.g., Pharos SignUp; Libraries already run Pharos Uniprint). Decouples
   guest auth from SIMS/Kerberos. Bigger project.
3. **Custom credential provider** — the subject of this document. The only option
   that keeps the exact current model (Kerberos + SIMS + per-guest local accounts)
   working on Entra-only devices.

---

## 3. How a custom credential provider solves it

### What a credential provider is

A credential provider is a **COM DLL** implementing the `ICredentialProvider`
interface. It is **not** a service, background process, or scheduled task. It sits
dormant on disk. When Windows shows the secure desktop (lock/logon screen),
`winlogon` → `LogonUI.exe` loads every registered provider, asks it to render tiles
and fields, and — on submit — calls its `GetSerialization()` method to package the
credential for LSA. Then it unloads. It runs only at the logon boundary, in the
`SYSTEM`/secure-desktop context. Nothing runs during a normal session.

### Why it bypasses the collision

The stock `PasswordProvider` treats `libguestN@UMD.EDU` as a **typed UPN string**
and does home-realm discovery on it → routed to Entra. A custom provider does not
parse a typed string; it fills the fields of a `KERB_INTERACTIVE_LOGON` structure
**directly and separately**:

```
DomainName = "UMD.EDU"      // the MIT realm, as a discrete field
UserName   = "libguestN"
Password   = <SIMS password>
```

and packages it (via `CredPackAuthenticationBuffer`) targeting the Kerberos/Negotiate
package. With domain and user as explicit separate fields, there's no `@`, no UPN,
no home-realm-discovery ambiguity for CloudAP to grab. LSA receives an explicit
`UMD.EDU` + `libguestN`, routes to the Kerberos SSP, which authenticates against the
KDC and applies the UserList mapping. **This is exactly what `runas` does** — the
successful runas test is proof this serialization works. The provider just moves
that call onto the lock screen.

### Two design routes

1. **Wrap the existing password provider** (recommended, less code): base it on
   Microsoft's `SampleWrapExistingCredentialProvider`. It wraps the stock
   `PasswordProvider`, reuses its UI, and intercepts `GetSerialization()` to rewrite
   the domain field to `UMD.EDU` when the username is a `libguest*` account.
2. **Standalone tile** (more code, cleaner UX): a dedicated "Library Guest Login"
   tile with its own username/password fields. Full `ICredentialProvider` +
   `ICredentialProviderCredential2` implementation.

---

## 4. Build process

Language is effectively fixed: **native C++ (COM)**. No PowerShell path exists;
C# / managed code in the logon path is discouraged and historically unsupported.

1. **Dev environment:** Visual Studio with "Desktop development with C++" workload +
   Windows SDK.
2. **Start from a Microsoft sample**, don't write from scratch:
   [Windows Classic Samples](https://github.com/microsoft/Windows-classic-samples)
   → `Samples/CredentialProvider` and `SampleWrapExistingCredentialProvider`.
3. **Make the one functional change:** in `GetSerialization()`, detect a `libguest*`
   username and set the domain field of the `KERB_INTERACTIVE_LOGON` to `UMD.EDU`
   before serialization.
4. **Build** an x64 DLL.
5. **Code-sign** the DLL (Authenticode). Not strictly required to load, but
   mandatory if WDAC / App Control / Smart App Control is in play, and expected by
   the security team.
6. **Test in a VM with snapshots — mandatory.** A broken provider can crash LogonUI
   or lock everyone (including admins) out. Snapshot → deploy → test at lock screen
   → roll back on failure. Never first-test on a machine you can't re-image. Always
   keep a known-working local-admin tile available.

---

## 5. Deployment via Intune (Win32 app)

Maps directly onto the existing `LibGuestCreation` Win32 packaging pattern; the only
new element is shipping a signed binary alongside the scripts.

- **Install** (PowerShell, runs as SYSTEM):
  1. Copy the signed DLL to a fixed path (e.g. `C:\Program Files\LibGuestCP\` or
     `System32`).
  2. Register the COM server:
     `HKCR\CLSID\{yourGUID}\InprocServer32` → (default) = DLL path,
     `ThreadingModel` = `Apartment`.
  3. Register the provider:
     `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{yourGUID}`.
  Write keys directly (`Test-Path` → `New-Item -Force` → `Set-ItemProperty -Force`)
  rather than `regsvr32` — idempotent and Intune-friendly.
- **Uninstall:** remove the provider registration FIRST (so LogonUI stops loading
  it), then the CLSID keys, then delete the DLL. This is also your **kill switch** —
  push the uninstall to instantly disable a misbehaving provider.
- **Detection:** the CLSID registry key exists (simple registry rule).
- **Reboot:** not required. The new tile appears at the next lock/sign-out because
  LogonUI reloads providers each time the secure desktop is shown.
- **Packaging:** the DLL is a payload file inside the `.intunewin`, same
  dual-method Win32 model documented in this folder's main `README.md`.

---

## 6. Prerequisites, risks, and gotchas

- **Runs as SYSTEM on the secure desktop.** High-privilege, security-sensitive.
  UMD security stack is CrowdStrike Falcon + Rapid7 InsightVM — **security-team
  review and sign-off is the real gate.** Do the concept review before writing code.
- **A bug = lockout.** Always ship with a working local-admin tile and a remote
  kill switch (see uninstall above). Test only in disposable VMs first.
- **You own it forever.** No Microsoft support if a Windows update changes behavior.
  Mitigating factor: the `ICredentialProvider` API has been stable in substance
  since Windows 8.
- **Signing:** required in practice for a trusted, WDAC-compatible deployment.
- **It handles plaintext credentials at logon** — expect scrutiny and document the
  data flow (credential is serialized into a KERB structure and handed to LSA; the
  provider does not store or transmit it anywhere else).

---

## 7. If/when I try this — starting prompt for an LLM

> I want to build a custom Windows credential provider to enable library guest
> logon on Entra-only devices. Full context is in this README
> (CustomCredentialProvider-Approach.md). Start me from Microsoft's
> `SampleWrapExistingCredentialProvider`: show me the specific `GetSerialization()`
> modification to rewrite the domain field to `UMD.EDU` for `libguest*` usernames,
> and give me the Intune Win32 install/uninstall/detection PowerShell scripts to
> deploy and register the signed DLL. Assume C++/Visual Studio and that I'll test in
> a snapshotted VM.

### Fastest path to real progress
1. **Security-team concept brief first** — if they won't bless a custom logon
   component, the C++ work is moot.
2. If blessed: build the wrap-provider from the sample, test in a VM.
3. Package + deploy with the Intune wrapper scripts (reuse this folder's pattern).

### Sanity-check before building
Re-confirm the premise still holds (Windows behavior changes):
```powershell
# On an Entra-only test box, with a live SIMS password — should still SUCCEED:
runas /user:libguestN@UMD.EDU cmd.exe
```
If that ever stops working, the whole approach is invalid and the problem is
elsewhere. If it works but the lock screen doesn't, the custom provider is still the
right tool.

### Also reconsider the alternatives each time
Hybrid-join (Section 2, option 1) remains the lower-risk answer. Only pursue the
custom provider if Entra-only is a hard requirement and the Entra-native redesign
(option 2) doesn't fit the service model.
