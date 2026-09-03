# NVivo 15 Silent Activation — Microsoft Intune Win32 App

## Table of Contents

- [[#Package Contents]]
- [[#Intune Configuration]]
- [[#Activation Profile]]
- [[#Detection and Logs]]
- [[#Uninstall Order]]
- [[#Security Notes]]
- [[#Rebuild]]
- [[#References]]

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
| `Source\NVivoLicense.ps1` | Ignored local script containing the product key |

The product key is stored only in `Source\NVivoLicense.ps1`. The workspace-level `.gitignore` excludes that key-bearing file from Git.

Generated package SHA256:

```text
39907817FDF9E2A5122A22676AF99001F8A5B8EDE8EA7CAB4999A01972FA4D9A
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

A restart is not required after activation. Close NVivo before running the activation app, then reopen it after Intune reports success. The activation wrapper returns an error if NVivo is already running, preventing activation against an open user session.

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
- The key is hardcoded in the ignored `Source\NVivoLicense.ps1` file at the user's request. `.gitignore` prevents accidental Git commits, but it does not encrypt or otherwise protect the local file.
- During activation, the vendor CLI requires the key on its process command line. SYSTEM administrators and endpoint security telemetry may observe it temporarily.
- The activation wrapper never writes the key or its command arguments to the UMD deployment log.
- Do not commit, email, or attach the generated package to tickets.

---

## Rebuild

> [[#Table of Contents|↑ Back to TOC]]

When the product key changes, open the ignored file below and replace only the value between the single quotation marks:

```powershell
# Source\NVivoLicense.ps1
$script:NVivoProductKey = 'PASTE-NEW-PRODUCT-KEY-HERE'
```

Then rebuild the package:

```powershell
Set-Location 'C:\Users\cmcleod1\OneDrive - University of Maryland\Documents\Work\StuffForWork\Intune\NVivo\15.5.2.4\Activation'
.\Build-NVivoActivationPackage.ps1
```

Do not paste the product key into any of these tracked files:

- `Source\Activate-NVivo.ps1`
- `Source\Activation.xml`
- `Source\Detect-NVivoActivation.ps1`
- This README or another documentation file

The relevant location in `Build-NVivoActivationPackage.ps1` is labeled `PRODUCT KEY LOCATION`. The builder validates that the ignored key file exists and includes it in `Output\Activate-NVivo.intunewin`.

After rebuilding, upload the new `.intunewin` as a replacement or superseding Intune app. The activation wrapper compares a non-reversible fingerprint, so a device previously activated by this package will run activation again when the packaged key changes.

---

## References

> [[#Table of Contents|↑ Back to TOC]]

- [Lumivero: Organization command-line installation and activation — NVivo 15 Windows](https://community.lumivero.com/s/article/NV15Win-Content-about-nvivo-ela-command-line-Win?language=en_US)
