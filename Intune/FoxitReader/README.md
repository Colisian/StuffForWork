# Foxit PDF Reader — Intune Win32 Package

Runbook for packaging and deploying Foxit PDF Reader 2026.1.2.36540 as an Intune Win32 app.

- **Owner:** Oji McLeod (cmcleod1@umd.edu) — ITFO / Digital Services & Technologies
- **Created:** 2026-08-12
- **Version:** 1.1.0

---

## Package facts

These were read directly out of the shipped binary, not assumed.

| Item | Value |
|---|---|
| Source binary | `FoxitPDFReader.exe` — Foxit Setup Bootstrapper, 376 MB |
| Bootstrapper version | `2026.1.2.36540` |
| Payload | `Setup.msi` + `Setup.msp` + 17 language `.mst` transforms |
| Base MSI version | `2025.2.0.33046` |
| Patched product version | `2026.1.2.36540` |
| Platform | **x64** → `C:\Program Files\Foxit Software\Foxit PDF Reader\` |
| ProductName | `Foxit PDF Reader` |
| ProductCode | `{01A75E1E-7567-11F0-B81F-54BF64A63C26}` — **rebuilt every release** |
| **UpgradeCode** | `{9D148992-FACF-4107-84A3-C48F19CF0B57}` — **stable, used for uninstall** |
| MSI features | `FX_PDFVIEWER`, `FX_SE`, `FX_SPELLCHECK`, `FX_FIREFOXPLUGIN`, `FX_IEBROWSER` |

> [!important] Deploy the EXE, not the MSI
> The bootstrapper installs `Setup.msi` (2025.2) and *then* applies `Setup.msp` to reach
> 2026.1.2.36540. Extracting and deploying `Setup.msi` on its own would leave the fleet on a
> version that is ~1 year stale and will be flagged by Rapid7 InsightVM.

### Bootstrapper switches

Recovered from the EXE's own embedded help text:

| Switch | Effect |
|---|---|
| `/quiet` | Silent install or uninstall |
| `/uninstall` | Uninstall |
| `/repair` | Repair the installation |
| `/extract <path>` | Extract payload (MSI/MSP/MST) without installing |
| `/lang <name>` | Force install language (`English`, `Deutsch`, `Nederlands`, …) |
| `/log <path>` | Installer log; defaults to `%temp%\foxit_setup.log` |
| `/noshortcut` | Suppress desktop shortcut |
| `/shortcut` | Force desktop shortcut |
| `/taskbar` | Pin to taskbar |
| `/DisableInternet` | Disable all features needing an outbound connection |
| `/DISABLE_UNINSTALL_SURVEY` | No browser survey on removal |
| `/clean` | Remove user data + registry on uninstall |
| `/force` | Overwrite a newer installed version |
| `/keycode <key>` | Activate a key code (not needed for free Reader) |

`/norestart` is **not** passed — the bootstrapper already suppresses reboot internally
(it strips the `SuppressReboot` custom action and sets `MSIRESTARTMANAGERCONTROL=Disable`).

---

## Files in this package

| File | Purpose |
|---|---|
| `FoxitPDFReader.exe` | Vendor bootstrapper (the payload) |
| `Install-FoxitReader.ps1` | Silent install wrapper |
| `Uninstall-FoxitReader.ps1` | Removal via UpgradeCode → ProductCode → `msiexec` |
| `Detect-FoxitReader.ps1` | Intune custom detection script |
| `README.md` | This runbook |

All three scripts are dual-method: they work when called with `-File` **and** when pasted into
Intune's Win32 "PowerShell script installer" box, because they resolve their own directory with
`if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }`.

> [!important] Parameter defaults are the intended build
> A pasted script has no command line, so it can never receive arguments. The defaults were
> therefore chosen to *be* the UMD Libraries build — running `Install-FoxitReader.ps1` with no
> parameters gives desktop shortcut **created**, uninstall survey **suppressed**, **English** UI,
> internet features **enabled**. Every switch opts *out* of that baseline, so a pasted copy and a
> bare command-line call behave identically. Do not add a switch to the command line without
> making the same change to any pasted copy.

| Script | Paste-safe? | Notes |
|---|---|---|
| `Install-FoxitReader.ps1` | ✅ 5.3 KB (10% of the 50 KB limit) | Defaults = intended build |
| `Uninstall-FoxitReader.ps1` | ✅ 7.4 KB (15%) | Only parameter is `-RemoveUserData`, which stays off |
| `Detect-FoxitReader.ps1` | n/a | Detection is a **file upload**, not a paste box; takes no parameters |

---

## 1. Build the `.intunewin`

Get `IntuneWinAppUtil.exe` from
[microsoft/Microsoft-Win32-Content-Prep-Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
(it is not currently on this workstation's PATH), then:

```powershell
$src = "$HOME\OneDrive - University of Maryland\Documents\Work\StuffForWork\Intune\FoxitReader"
$out = "$HOME\OneDrive - University of Maryland\Documents\Work\StuffForWork\Intune\_Output"
New-Item -ItemType Directory -Force -Path $out | Out-Null

IntuneWinAppUtil.exe -c $src -s "FoxitPDFReader.exe" -o $out -q
```

`-s` is a required placeholder for script-driven installs — pointing it at any bundled file is
fine. Expect the output to be roughly 350–380 MB and the build to take a few minutes.

---

## 2. Intune app configuration

**Apps → Windows → Add → Windows app (Win32)**

### Program

Two supported methods. **Method A is preferred** — the wrapper is then versioned inside the
`.intunewin`, so the copy in this repo is the copy that runs.

#### Method A — command line (default)

| Field | Value |
|---|---|
| Install command | `powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-FoxitReader.ps1` |
| Uninstall command | `powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-FoxitReader.ps1` |
| Install behavior | **System** |
| Device restart behavior | **No specific action** |

No switches are needed — the defaults are the intended build. Add `-NoDesktopShortcut` and/or
`-DisableInternet` for lab and kiosk rings; see [Auto-update: pick one](#auto-update-pick-one).

#### Method B — pasted PowerShell script installer

Paste the full contents of `Install-FoxitReader.ps1` and `Uninstall-FoxitReader.ps1` into the
respective boxes. Both are comfortably under the 50 KB limit and neither relies on
`$PSScriptRoot`, so no edits are required.

Trade-off: there is no command line, so **no arguments can be passed** — you get exactly the
default build described above. To vary it (a `-DisableInternet` lab ring, say), edit the pasted
copy's `param()` defaults in the portal, and note that this is the point at which the portal
copy and this repo can silently drift. Keep `FoxitPDFReader.exe` bundled in the `.intunewin`
either way; the paste box replaces the wrapper, not the payload.

### Return codes

| Code | Mapping |
|---|---|
| 0 | Success |
| 3010 | Soft reboot |
| 1641 | Hard reboot |
| 1 | Failed |

### Requirements

- Operating system architecture: **x64** (the payload MSI is x64-only)
- Minimum OS: Windows 10 1809 or later
- Disk space: allow ~1.5 GB free — the bootstrapper unpacks ~360 MB of payload to `%temp%`
  before handing off to `msiexec`

### Detection rule

- Rules format: **Use a custom detection script**
- Script file: `Detect-FoxitReader.ps1`
- Run script as 32-bit process on 64-bit clients: **No**
- Enforce script signature check: **No**

The script anchors on the ARP `DisplayVersion` with a floor of `2026.1.0.0` — above the
unpatched base MSI (2025.2.0.33046) and at/below the patched product. A run where the MSI
landed but the MSP failed is therefore correctly reported as **not installed** rather than
silently passing. The `-ge` comparison also means Foxit's own auto-updater bumping the build
will not cause false "not detected" churn.

> [!note] Detection script exit contract
> Win32 detection is *not* the Remediations contract. Detected = exit 0 **with** STDOUT;
> not detected = exit 0 with **empty** STDOUT. The script never exits non-zero.

---

## 3. Verification

Run on a test device after the install lands:

```powershell
# ARP registration — this is what detection reads
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' |
    Get-ItemProperty |
    Where-Object DisplayName -like 'Foxit PDF Reader*' |
    Select-Object DisplayName, DisplayVersion, InstallLocation

# On-disk product version — should read 2026.1.2.36540
(Get-Item 'C:\Program Files\Foxit Software\Foxit PDF Reader\FoxitPDFReader.exe').VersionInfo.ProductVersion

# Exercise the detection script exactly as Intune will
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Detect-FoxitReader.ps1
"exit=$LASTEXITCODE"   # expect exit=0 with a 'Detected: ...' line
```

Confirm the observed `DisplayVersion` on the first test box. If Foxit's ARP version string
turns out to differ in shape from the file version, the `2026.1.0.0` floor still holds — only
adjust `$minimumVersion` if the ARP value is unexpectedly below it.

### Logs

| Log | Path |
|---|---|
| Install transcript | `C:\ProgramData\FoxitReader\Install-FoxitReader.log` |
| Uninstall transcript | `C:\ProgramData\FoxitReader\Uninstall-FoxitReader.log` |
| Foxit native installer | `C:\ProgramData\FoxitReader\foxit_setup.log` |
| MSI uninstall verbose | `C:\ProgramData\FoxitReader\foxit_uninstall.log` |
| Intune agent | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` |

---

## Operational notes

### Default PDF handler

The MSI ships `MAKEDEFAULT=1`, but **this will not work on Windows 10/11** — the OS protects
file-type associations and ignores installer-set defaults. If Foxit needs to own `.pdf`,
deploy a separate **Settings Catalog** policy using
*Administrative Templates → Windows Components → File Explorer → Set a default associations
configuration file*, pointing at an associations XML with `.pdf` mapped to Foxit's ProgID.
Read the ProgID off a manually configured reference machine first.

### Auto-update: pick one

| Approach | Pros | Cons |
|---|---|---|
| **Leave updater on** (default) | Foxit self-patches CVEs between your repackages; less Rapid7 noise | Fleet version drifts; outbound Foxit traffic from every client |
| **`-DisableInternet`** | No telemetry, no ConnectedPDF, no cloud plug-ins; you own the version | You must repackage and redeploy for **every** security update, or InsightVM will light up |

For lab and kiosk builds where the image is rebuilt on a schedule, `-DisableInternet` is the
better fit. For staff laptops, leaving the updater on is usually safer.

### Security callouts

- **CrowdStrike Falcon** — a 376 MB self-extracting binary unpacking to `%temp%` and spawning
  `msiexec` is a textbook dropper pattern. Run the first deployment against a small pilot ring
  and check for detections before broad release.
- **Rapid7 InsightVM** — Foxit Reader is a recurring CVE target. Whichever update approach you
  pick above, make sure *something* owns patching it.
- **PDF JavaScript** — Foxit executes JS in PDFs by default, the same class of attack surface
  that drove Adobe hardening. Consider disabling JS and enabling Safe Reading Mode via a
  follow-up registry Win32 app or Platform Script. Verify the exact policy key names against
  Foxit's current *Deployment and Configuration* guide rather than copying values from older
  blog posts — they have changed between major versions.
- No credentials are present in this package; nothing here needs Secrets Manager.

### Uninstall design

`Uninstall-FoxitReader.ps1` deliberately does **not** depend on the 376 MB bootstrapper. It
resolves live ProductCodes from the stable UpgradeCode via `WindowsInstaller.Installer`
`RelatedProducts` and calls `msiexec /x`, so it keeps working after a version bump changes the
ProductCode. The bootstrapper and `QuietUninstallString` remain as ordered fallbacks.

Pass `-RemoveUserData` (adds `CLEAN=1` / `/clean`) only when you intend to destroy user
preferences and stamps — it is not the default.
