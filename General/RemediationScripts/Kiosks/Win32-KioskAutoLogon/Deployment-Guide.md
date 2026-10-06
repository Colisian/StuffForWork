# UMD Libraries — Kiosk Auto-Logon Win32 Deployment

**Deployment version:** `2026.10.06.2`  
**Prepared:** October 6, 2026

## Table of Contents

- [[#Purpose]]
- [[#Files and Locations]]
- [[#Intune Setup]]
- [[#PowerShell Script Installer Method]]
- [[#AxisTV Startup]]
- [[#Repair and Detection]]
- [[#Force a Future Repair]]
- [[#Rebuild the Package]]
- [[#Pilot Verification]]
- [[#Logs and Troubleshooting]]
- [[#Security and Policy Notes]]
- [[#Uninstall]]
- [[#Validation Completed]]
- [[#References]]

---

## Purpose
> [[#Table of Contents|↑ Back to TOC]]

Repair automatic logon for the existing **LibCirc** local account through an Intune Win32 app. This carries forward the behavior of `General\RemediationScripts\Kiosks\LIBR_Kiosk.ps1`. The original script is unchanged.

The app does not configure Windows Assigned Access, create accounts, change kiosk application restrictions, restart devices, or sign out the current user. Auto-logon takes effect at the next sign-in or restart.

---

## Files and Locations
> [[#Table of Contents|↑ Back to TOC]]

| File | Purpose |
|---|---|
| `Output\Install-KioskAutoLogon.intunewin` | Initial package to upload to Intune |
| `Detect-KioskAutoLogon.ps1` | Custom detection script, uploaded separately |
| `Source\Install-KioskAutoLogon.ps1` | Install and repair wrapper |
| `Source\Uninstall-KioskAutoLogon.ps1` | Disable automatic logon |
| `Source\NativeAutologon.cs` | LSA secret helper |
| `Source\KioskConfig.json` | Account name, deployment version, and policy-cleanup setting |
| `Source\KioskPassword.txt` | Existing password carried over from the original script; sensitive |

**Authoring directory:**

```text
C:\Users\cmcleod1\OneDrive - University of Maryland\Documents\Work\StuffForWork\General\RemediationScripts\Kiosks\Win32-KioskAutoLogon
```

**Build mirror and endpoint log root:**

```text
C:\ProgramData\UMDLibraries\KioskAutoLogon
```

---

## Intune Setup
> [[#Table of Contents|↑ Back to TOC]]

1. Open **Apps → Windows → Add → Windows app (Win32)**.
2. Upload `Output\Install-KioskAutoLogon.intunewin`.
3. Set the name to **UMD Libraries - Kiosk Auto-Logon Repair 2026.10.06.2** and publisher to **University of Maryland Libraries**.
4. Configure the Program settings below, or use [[#PowerShell Script Installer Method]].

| Program setting | Value |
|---|---|
| Install behavior | **System** |
| Device restart behavior | **No specific action** |
| Return code `0` | Success |
| Return code `1` | Failed |

**Install command** — paste as one line:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Install-KioskAutoLogon.ps1
```

**Uninstall command** — paste as one line:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Uninstall-KioskAutoLogon.ps1
```

5. Configure requirements for **x64 Windows 10/11**, with minimum Windows 10 1607 or your higher organizational baseline. Target supported Windows releases only. The existing `LibCirc` account must be enabled.
6. Configure detection:

| Detection setting | Value |
|---|---|
| Rules format | **Use a custom detection script** |
| Script file | `Detect-KioskAutoLogon.ps1` |
| Run script as 32-bit process on 64-bit clients | **No** |
| Enforce script signature check | **No** — current scripts are unsigned |

Use the custom script alone; do not add a file/folder detection rule.

7. Assign **Required** to a small kiosk **device** pilot group, then expand to the kiosk fleet after verification. Remove or exclude the old platform-script assignment for these devices to prevent overlapping management.
8. Sync pilot devices, confirm installation, and schedule one pilot restart to verify unattended logon.

The scripts do not initiate restarts or return `3010`.

---

## PowerShell Script Installer Method
> [[#Table of Contents|↑ Back to TOC]]

Both wrappers support the **PowerShell script installer option inside the Win32 app** without edits.

1. Upload the same `.intunewin` package.
2. Select **PowerShell script** for installation. Upload or paste `Source\Install-KioskAutoLogon.ps1`, as offered by the Intune interface.
3. Select **PowerShell script** for uninstallation. Upload or paste `Source\Uninstall-KioskAutoLogon.ps1`.
4. Use **System** install behavior and native **64-bit** execution.
5. Upload `Detect-KioskAutoLogon.ps1` separately as custom detection, with 32-bit execution set to **No**.

**The `.intunewin` package is still required:** it supplies the configuration, password file, and native LSA helper. Each wrapper resolves companion files using `$PSScriptRoot`, or the unpacked package working directory when pasted. Both wrappers are below the 50 KB pasted-script limit.

The command-line method keeps the executable scripts versioned inside the package and is the default. This alternative uses the installer fields in a Win32 app, rather than **Devices → Scripts and remediations → Platform scripts**.

---

## AxisTV Startup
> [[#Table of Contents|↑ Back to TOC]]

Version **2026.10.06.2** adds the existing AxisTV playback shortcut to **All Users Startup**.

| Setting | Path |
|---|---|
| Existing vendor shortcut | `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\AxisTV Engage\Start AxisTV Engage Playback.lnk` |
| Managed startup copy | `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\UMD-AxisTV Engage Playback.lnk` |

The installer resolves Windows' Common Startup folder and copies the complete shortcut, preserving its target, arguments, and working directory. Windows launches it in the signing-in user's session, including when **LibCirc** logs in automatically. All Users Startup also applies to other interactive users on the kiosk.

**Prerequisite:** AxisTV Engage and the vendor shortcut must already be installed. A missing shortcut fails installation before account or auto-logon changes. If AxisTV is separately deployed as a Win32 app, consider configuring it as an Intune dependency.

Detection requires the source and startup copies to exist and match by SHA-256 hash, and to match the ownership hash recorded in the deployment marker. A removed or altered startup shortcut fails detection.

Uninstall removes the startup copy only when its hash matches the recorded deployment hash. A modified or untracked shortcut is retained with a log message. The original vendor shortcut and AxisTV application remain in place.

**Deploy the update:** replace the Intune app package and custom detection script with version **2026.10.06.2**. If using the PowerShell script installer fields, also replace the install and uninstall scripts. Keep the Required device assignment; the new version makes the previous deployment fail detection.

**Pilot check:** confirm the managed startup shortcut exists, then sign in as LibCirc or restart during a maintenance window and confirm playback opens. Check Windows Startup Apps if startup entries were disabled. Remove a redundant AxisTV startup mechanism if it causes duplicate launches. File detection does not prove playback started or that Windows allowed the startup entry.

---

## Repair and Detection
> [[#Table of Contents|↑ Back to TOC]]

The first Win32 deployment runs even if the old platform script already configured auto-logon, because the old deployment has no matching Win32 completion marker.

The installer updates the existing account password, disables account and password expiration, optionally removes DeviceLock keys, stores the password as an LSA secret, and configures unlimited local auto-logon. After basic verification, it writes `DeploymentVersion` under:

```text
HKLM\SOFTWARE\UMDLibraries\KioskAutoLogon
```

Detection checks:

- Exact deployment version and expected account.
- Enabled local account with a nonexpiring password and unexpired account.
- `AutoAdminLogon = 1`, expected username, and local computer domain.
- No plaintext Winlogon `DefaultPassword` and no `AutoLogonCount` limit.
- A nonempty `DefaultPassword` LSA secret.
- Matching source and managed AxisTV startup shortcuts, with a recorded ownership hash.

Detection exits `0` with output when installed; otherwise, it exits `1` silently. Required Win32 apps can be offered again when Intune reevaluates them as missing. Repair is eventual; this does not provide immediate monitoring or a guaranteed check interval.

Detection does not validate the secret against the actual account password, detect every policy conflict, or prove successful unattended logon after a reboot.

---

## Force a Future Repair
> [[#Table of Contents|↑ Back to TOC]]

1. Increment `DeploymentVersion` in `Source\KioskConfig.json`, for example to `2026.10.06.3`.
2. Set `$requiredVersion` in `Detect-KioskAutoLogon.ps1` to the same value. If changing the account, also update `$expectedUser`.
3. Follow [[#Rebuild the Package]].
4. Replace **both the app package and the uploaded detection script** in Intune, keeping the Required assignment. The old deployment version will fail detection and trigger another install when evaluated.

Syncing or replacing content with the same version does not force another run when detection still passes. For scheduled policy repair, consider Intune Remediations as a separate option.

---

## Rebuild the Package
> [[#Table of Contents|↑ Back to TOC]]

After editing the authoring files, refresh the build mirror and rebuild:

```powershell
Set-Location 'C:\Users\cmcleod1\OneDrive - University of Maryland\Documents\Work\StuffForWork\General\RemediationScripts\Kiosks\Win32-KioskAutoLogon'

Copy-Item -Path .\Source, .\Detect-KioskAutoLogon.ps1 `
    -Destination 'C:\ProgramData\UMDLibraries\KioskAutoLogon' -Recurse -Force

& 'C:\ProgramData\UMDLibraries\Tools\IntuneWinAppUtil-1.8.7.exe' `
    -c 'C:\ProgramData\UMDLibraries\KioskAutoLogon\Source' `
    -s 'Install-KioskAutoLogon.ps1' `
    -o 'C:\ProgramData\UMDLibraries\KioskAutoLogon\Output' -q

if ($LASTEXITCODE -ne 0) { throw 'Win32 package build failed.' }
```

Upload the **newly built package** from:

```text
C:\ProgramData\UMDLibraries\KioskAutoLogon\Output\Install-KioskAutoLogon.intunewin
```

The authoring directory's `Output` copy is the initial package unless refreshed. Also upload the updated detection script. If using the PowerShell script installer fields, update those scripts whenever the wrappers change.

The `-s` argument is a required setup-file placeholder for this script package. Keep output and tool files outside `Source` so they are not included in the package.

---

## Pilot Verification
> [[#Table of Contents|↑ Back to TOC]]

Run these read-only checks in elevated **64-bit Windows PowerShell** on the pilot:

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\UMDLibraries\KioskAutoLogon'

Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' |
    Select-Object AutoAdminLogon, DefaultUserName, DefaultDomainName, AutoLogonCount

Get-LocalUser -Name LibCirc |
    Select-Object Name, Enabled, PasswordExpires, AccountExpires

Get-Content 'C:\ProgramData\UMDLibraries\KioskAutoLogon\Logs\Install-KioskAutoLogon.log' -Tail 30
```

Evaluate uploaded detection through Intune as **SYSTEM**. A manual check without sufficient privileges may fail when accessing LSA secrets.

Test a restart during a maintenance window. Successful installation alone does not prove unattended logon works.

---

## Logs and Troubleshooting
> [[#Table of Contents|↑ Back to TOC]]

| Log | Location |
|---|---|
| Install | `C:\ProgramData\UMDLibraries\KioskAutoLogon\Logs\Install-KioskAutoLogon.log` |
| Uninstall | `C:\ProgramData\UMDLibraries\KioskAutoLogon\Logs\Uninstall-KioskAutoLogon.log` |
| Intune agent | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs` |

Start with account existence and enabled state, password-policy compatibility, native 64-bit System execution, and bundled configuration file presence. Then check for conflicting Intune DeviceLock, logon-message, or account-management policies.

Failure logs identify the error type and script line without printing raw credential-operation exceptions.

---

## Security and Policy Notes
> [[#Table of Contents|↑ Back to TOC]]

**The package contains a credential.** `KioskPassword.txt` stores the existing password as plaintext. Converting it to a `SecureString` protects how the account cmdlet receives it; it does not protect the bundled file. Administrators and endpoint SYSTEM/admin access can recover the credential from packaged or unpacked content.

- Generated package directories are restricted locally to SYSTEM, local Administrators, and the creating user. Local permissions do not govern cloud sharing of the OneDrive copy.
- Do not commit the credential or package to Git, attach it to tickets, or distribute it broadly.
- Rotate the shared password through your approved process: update the bundled file, increment the deployment version, and rebuild.
- The installer does not copy the password into endpoint deployment logs; Intune's unpacked content/cache can still contain it.
- Keep the kiosk account nonadministrative. Physical users receive the account's access through auto-logon; local administrators/SYSTEM can access LSA secrets.

`RemoveDeviceLockPolicies` is `true` to match the original working repair. Removing these keys can weaken lock protections. Scope the app strictly to kiosks and correct conflicting policy assignments or exclusions in Intune; assigned policies can reapply the keys. Set the flag to `false` and rebuild if cleanup is unnecessary.

Keep CrowdStrike and Rapid7 enabled. If account-password or LSA changes raise detections, review with security staff and use narrowly scoped, approved exceptions only.

---

## Uninstall
> [[#Table of Contents|↑ Back to TOC]]

Remove the **Required** assignment before assigning **Uninstall**.

Uninstall removes the unchanged managed AxisTV startup shortcut, disables auto-logon, removes the LSA password and completion marker, and retains the local account, its password, and the current session. It refuses to change a different configured auto-logon username.

It does not restore deleted policy keys or the prior password. Reapply desired DeviceLock settings through Intune.

---

## Validation Completed
> [[#Table of Contents|↑ Back to TOC]]

- PowerShell syntax checks passed.
- The native LSA helper compiled, including under Windows PowerShell 5.1.
- Microsoft's content preparation tool successfully created the package.
- Read-only detection returned not installed on the authoring computer.
- No account, password, Winlogon, DeviceLock, or LSA changes were executed on the authoring computer.

Live SYSTEM deployment and reboot auto-logon still require pilot validation.

---

## References
> [[#Table of Contents|↑ Back to TOC]]

- [Add and assign Win32 apps in Microsoft Intune](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)
- [Prepare a Win32 app for upload](https://learn.microsoft.com/en-us/intune/app-management/deployment/create-win32-package)
- [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)

