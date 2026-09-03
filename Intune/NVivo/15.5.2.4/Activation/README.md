# NVivo 15 Silent Activation — Microsoft Intune Win32 App

## Table of Contents

- [[#Package Contents]]
- [[#Intune Configuration]]
- [[#Activation Profile]]
- [[#Detection and Logs]]
- [[#Uninstall Order]]
- [[#Security Notes]]
- [[#Rebuild]]

---

## Package Contents

> [[#Table of Contents|↑ Back to TOC]]

| Item | Purpose |
|---|---|
| `Output\Activate-NVivo.intunewin` | Upload as a separate Windows app (Win32) |
| `Source\Activate-NVivo.ps1` | Runs machine activation under SYSTEM |
| `Source\Deactivate-NVivo.ps1` | Releases the managed license before removal |
| `Source\Detect-NVivoActivation.ps1` | Custom activation detection script |
| `Source\Activation.xml` | Lumivero activation profile without the product key |

The unencrypted source folder intentionally contains no product key.

Generated package SHA256:

```text
116DA2A9B91DEB90B1CE91DD41117C7258ACBFFB103783CD62A7C8145FD1E75B
```

---

## Intune Configuration

> [[#Table of Contents|↑ Back to TOC]]

| Setting | Value |
|---|---|
| Name | NVivo 15 — Silent Activation |
| Publisher | University of Maryland Libraries / Lumivero |
| Install behavior | System |
| Device restart behavior | No specific action |
| Dependency | NVivo 15.5.2.4 Win32 app |
| 32-bit Windows | No |

**Install command:**

```powershell
%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Activate-NVivo.ps1
```

**Uninstall command:**

```powershell
%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Deactivate-NVivo.ps1
```

Assign this app to the same device group as NVivo after adding NVivo 15.5.2.4 as a dependency.

---

## Activation Profile

> [[#Table of Contents|↑ Back to TOC]]

`Activation.xml` currently identifies University of Maryland Libraries ITFO using `cmcleod1@umd.edu`. Confirm that Lumivero accepts these organization details during the pilot. Change the XML and rebuild if the licensing contact must use different values.

The license format indicates a version 14 entitlement. Confirm in MyLumivero that it is an active subscription or organizational license eligible to activate NVivo 15.

---

## Detection and Logs

> [[#Table of Contents|↑ Back to TOC]]

Select **Use a custom detection script** and upload:

```text
Source\Detect-NVivoActivation.ps1
```

Configure **Run script as 32-bit process on 64-bit clients** as **No**. Detection requires NVivo.exe and a registry sentinel written only after the activation command returns success.

Endpoint logs contain no product key and remain under:

```text
C:\ProgramData\UMDLibraries\NVivo\
```

---

## Uninstall Order

> [[#Table of Contents|↑ Back to TOC]]

Deactivate before uninstalling the base NVivo application:

1. Assign **Uninstall** to `NVivo 15 — Silent Activation`.
2. Confirm successful deactivation in Intune and `Deactivate-NVivo.log`.
3. Assign **Uninstall** to `NVivo 15.5.2.4`.

Deactivation requires Internet access to Lumivero. The deactivation wrapper deliberately fails without deleting its sentinel when Lumivero does not confirm success.

---

## Security Notes

> [[#Table of Contents|↑ Back to TOC]]

- The generated `.intunewin` contains organizational license material. Restrict access to the output directory and the Intune app.
- The build process places the key only in a temporary staging directory and removes that directory immediately after packaging.
- During activation, the vendor CLI requires the key on its process command line. SYSTEM administrators and endpoint security telemetry may observe it temporarily.
- The activation wrapper never writes the key or its command arguments to the UMD deployment log and deletes the transient key file after reading it.
- Do not commit, email, or attach the generated package to tickets.

---

## Rebuild

> [[#Table of Contents|↑ Back to TOC]]

When the product key changes, run the builder interactively:

```powershell
Set-Location 'C:\Users\cmcleod1\OneDrive - University of Maryland\Documents\Work\StuffForWork\Intune\NVivo\15.5.2.4\Activation'
.\Build-NVivoActivationPackage.ps1
```

PowerShell displays this prompt:

```text
Enter the NVivo enterprise key:
```

**Paste the new product key at that prompt and press Enter.** The characters are intentionally hidden while you paste or type them. This is the only place where the key should be entered.

Do not paste the product key into any of these files:

- `Source\Activate-NVivo.ps1`
- `Source\Activation.xml`
- `Source\Detect-NVivoActivation.ps1`
- This README or another documentation file

The relevant location in `Build-NVivoActivationPackage.ps1` is labeled `PRODUCT KEY ENTRY POINT`. The builder places the key into temporary packaging space, generates a new `Output\Activate-NVivo.intunewin`, and removes the temporary plaintext copy. It does not save the key in `Source`.

After rebuilding, upload the new `.intunewin` as a replacement or superseding Intune app. The activation wrapper compares a non-reversible fingerprint, so a device previously activated by this package will run activation again when the packaged key changes.
