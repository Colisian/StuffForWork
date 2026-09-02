# Adobe Product Uninstall (keep Creative Cloud) — Intune Win32 App

Removes every Adobe product from a device **except the Adobe Creative Cloud desktop app** (and Adobe Genuine Service, which CC depends on and would silently reinstall). Complements `LIB-AdobeInstallerCleanup.ps1`, which targets Acrobat installer-cache growth; this script is the general "wipe Adobe apps, keep the launcher" tool.

## Contents

| File | Purpose |
| --- | --- |
| `Uninstall-AdobeProducts.ps1` | Enumerates Adobe entries in both Uninstall hives, keeps anything matching `-KeepPattern`, silently removes the rest with the right mechanism per installer type |
| `Detect-AdobeUninstall.ps1` | Custom detection: sentinel `Completed=1` **and** a live re-check that no non-kept Adobe product exists |
| `AdobeUninstaller.exe` *(optional, not in repo)* | Adobe's supported bulk uninstaller. Download from **Admin Console → Packages → Tools → Adobe Uninstaller**. Drop it next to the script before packaging and it is used first for CC apps |

## How products are removed

| Installer type | How it is identified | Command used |
| --- | --- | --- |
| Creative Cloud / HyperDrive apps (Photoshop, Illustrator, InDesign, Premiere, After Effects, Lightroom, Bridge, Substance…) | `UninstallString` contains `--sapCode=` / `HDBox\` | 1. `AdobeUninstaller.exe --products=PHSP#25.0,ILST#28.0 --skipNotInstalled` if bundled. 2. Otherwise Adobe's silent engine `HDBox\Setup.exe --uninstall=1 --sapCode=… --baseVersion=… --platform=win64 --deleteUserPreferences=false`, with sapCode/version parsed from the registry string. **The registry `UninstallString` itself is never run** (see *Lessons from the first live run*) |
| MSI (Acrobat, Reader, Refresh Manager, AIR…) | `WindowsInstaller=1` or `msiexec` in `UninstallString` | `msiexec /x {ProductCode} /qn /norestart REBOOT=ReallySuppress` |
| Other EXE (Digital Editions, etc.) | everything else | `QuietUninstallString` if present, else `UninstallString /S` (best effort) |
| **Admin Console package wrappers** (`AdobeCC_SelfService`, `Adobe.CC.201902`, `LIBR-AcrobatDC`…) | MSI with `DisplayVersion = 1.0.0000` | **Skipped by default** and ignored by detection. These are package registrations, not apps; uninstalling one removes every product in that package, and a self-service package's only product is the CC desktop app. `-RemovePackageWrappers` includes them |
| Legacy CS5/CS6/early-CC (`PDApp.exe`) | `PDApp.exe` in `UninstallString` | **Skipped with WARN** — no silent mode exists; use the Creative Cloud Cleaner Tool |

Every uninstaller runs under a hard timeout (`-TimeoutMinutes`, default 30) and is killed if it hangs, so a stray prompt can't wedge the Intune install. `Win32_Product` is never queried (it triggers MSI self-repair on every product on the machine).

Processes are stopped by **path**: anything running from `Program Files\Adobe\*` or `Program Files (x86)\Adobe\*` that does not match a keep pattern or the built-in `$ProtectedPathPattern` (`Adobe Creative Cloud`, `Creative Cloud Experience`, `Adobe Sync` [CoreSync], `Adobe Desktop Common`, `AdobeGCClient`). Creative Cloud's runtime under `Common Files\Adobe\*` is never in scope. The same protected list guards `-RemoveLeftoverFolders`.

## Parameters

| Parameter | Default | Notes |
| --- | --- | --- |
| `-KeepPattern` | `'Adobe Creative Cloud','Adobe Genuine Service'` | Regex list matched against `DisplayName`. Add `'Adobe Acrobat'` to keep Acrobat, etc. Keep `Detect-AdobeUninstall.ps1` in sync |
| `-RemoveUserPreferences` | off | Passes `--deleteUserPreferences=true` to the CC app uninstaller |
| `-RemovePackageWrappers` | off | Also `msiexec /x` the Admin Console package wrapper MSIs. **A self-service wrapper removes the CC desktop app** — only use on devices where the wrappers are known to contain apps only |
| `-RemoveLeftoverFolders` | off | Deletes orphan folders under `Program Files\Adobe` / `(x86)` that no remaining product owns. Never touches `Common Files\Adobe` |
| `-AdobeUninstallerPath` | `<script dir>\AdobeUninstaller.exe` | Override location of Adobe's tool |
| `-TimeoutMinutes` | 30 | Per-uninstaller kill timer |
| `-WhatIf` | | Inventory + plan only, no changes, no sentinel |

## Outputs

- Log: `C:\ProgramData\LIBR\Logs\AdobeUninstall-<yyyyMMdd-HHmmss>.log`
- Sentinel: `HKLM\SOFTWARE\LIBR\AdobeUninstall` → `Completed` (DWORD 1/0), `Remaining`, `ScriptVersion`, `LastRun`, `LastLog`
- Exit codes: `0` all removed · `3010` all removed, reboot required · `1` not admin or products remain

## Package

```powershell
# Optional: copy AdobeUninstaller.exe into General\AdobeClean first
IntuneWinAppUtil.exe -c "<repo>\General\AdobeClean" -s Uninstall-AdobeProducts.ps1 -o "<output-folder>"
```

## Intune app — Method A (command line, preferred: script is versioned inside the package)

| Setting | Value |
| --- | --- |
| Install command | `%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File Uninstall-AdobeProducts.ps1` |
| Uninstall command | `cmd /c exit 0` *(nothing to reverse — reinstall apps via CC / Patch My PC)* |
| Install behavior | **System** |
| **Maximum allowed install time** | **240 minutes** (default is 60 — see *Runtime* below; the app is marked failed at the limit even while it is still working) |
| Device restart behavior | Determine behavior based on return codes |
| Return codes | `0` Success · `3010` Soft reboot · `1` Failed |
| Detection | Custom script → `Detect-AdobeUninstall.ps1` (Run as 32-bit: No) — or a registry rule: `HKLM\SOFTWARE\LIBR\AdobeUninstall`, value `Completed`, Integer equals `1` |

Add `-RemoveLeftoverFolders` / `-KeepPattern ...` to the install command as needed. If both variants of the app exist, give them distinct sentinel keys by editing `$SentinelKey` (and the detection script).

## Intune app — Method B (PowerShell script installer, paste)

Set **Installer type = PowerShell script** and paste `Uninstall-AdobeProducts.ps1` (30 KB, under the 50 KB paste limit). The script locates `AdobeUninstaller.exe` via the current directory when `$PSScriptRoot` is empty, so bundling it in the `.intunewin` still works. Hot-fixes made in the portal must be synced back to this repo.

## Lessons from the first live run (2026-09-01, v1.1.0, `LIBRWKSPC010189`)

The first real run reported 16 removals in 32 seconds and removed nothing. Every app's registry `UninstallString` on current CC builds looks like:

```
"…\HDBox\Uninstaller.exe" --uninstall=1 --sapCode=PHSP --productVersion=27.10 --productPlatform=win64 --productAdobeCode={…} --productName="Photoshop" --mode=2
```

That is the **Programs and Features launcher**, not an uninstaller. It hands the job to the Creative Cloud desktop app (hence the sign-in window that popped for every app), then exits 0 after ~2 seconds. Under SYSTEM there is no desktop to hand off to, so it silently does nothing. v1.2.0 therefore:

- Ignores the registry command and builds Adobe's documented silent command against `HDBox\Setup.exe`. Note that HDBox contains **both** `Setup.exe` (~850 KB, the HyperDrive engine, macOS twin is `HDBox/Setup`) and `Set-up.exe` (~14 MB, the Creative Cloud installer bootstrapper). The script prefers `Setup.exe` and logs which one it used.
- **Credits a removal only when the product's Uninstall key has disappeared.** Exit codes from Adobe launchers are not trusted. Each uninstall also logs its duration; ~2 s means nothing happened.

Before re-running on that device, dismiss any Creative Cloud sign-in / uninstall dialogs the v1.1.0 run left open, otherwise the HD engine may report another instance is running.

## Runtime — read before assigning

Creative Cloud apps are uninstalled **sequentially**, and each HDBox uninstall realistically takes 2–8 minutes. A fully loaded device (18 targets measured on `LIBRWKSPC010189`) can therefore run **30–130 minutes**. Two consequences:

1. **Raise Intune's "Maximum allowed install time" to 240 minutes.** At the 60-minute default Intune reports the app as failed while the uninstall is still running, and may retry it on top of itself.
2. **Bundle `AdobeUninstaller.exe`.** It removes all CC apps in a single pass and is dramatically faster than the per-app fallback. Without it the script logs `AdobeUninstaller.exe not found at <dir> - using per-app HDBox uninstaller` and takes the slow path.

`-TimeoutMinutes` (default 30) is a per-uninstaller kill timer, **not** a total budget. It exists to stop one hung uninstaller, not to bound the whole run. The summary logs `Elapsed` so you can size the Intune timeout from real fleet data.

## Verify on a device

```powershell
# Dry run as admin: shows KEEP/REMOVE plan, changes nothing
.\Uninstall-AdobeProducts.ps1 -WhatIf

# Latest log
Get-ChildItem C:\ProgramData\LIBR\Logs\AdobeUninstall-*.log | Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Content

# Sentinel
Get-ItemProperty HKLM:\SOFTWARE\LIBR\AdobeUninstall

# What Adobe is still registered
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
  Where-Object { $_.Publisher -match '^Adobe' -or $_.DisplayName -match '^Adobe' } |
  Select-Object DisplayName, DisplayVersion, UninstallString

# Detection result as Intune sees it
powershell -File .\Detect-AdobeUninstall.ps1; $LASTEXITCODE
```

## Caveats / security notes

- **Acrobat is removed** unless you add `'Adobe Acrobat'` to `-KeepPattern`. On the LIBR fleet Acrobat is owned by DIT via Patch My PC; coordinate before mass-deploying or PMPC will just put it back.
- Creative Cloud will show removed apps as "Install" again — expected. Users with a CC entitlement can reinstall; kiosk/lab images should have CC self-service restricted via the Admin Console package options.
- User data in `AppData\*\Adobe` is **not** touched (the CC desktop app shares those folders). Use `Clean-Adobe.ps1` only when CC is also being removed.
- CrowdStrike/Rapid7: mass process kills + `msiexec /x` from SYSTEM are normal Intune behavior and match the existing cleanup app's footprint; no new detections expected.
- `UXP WebView Support` is an HD shared runtime used by CC apps (not by the CC desktop app itself) and is removed with them; CC reinstalls it on demand.
- Verified on `LIBRWKSPC010189` (2026-09-01, `-WhatIf`, v1.1.1): 18 targets (16 HD apps + 2 MSIs), 3 package wrappers skipped, CC desktop app + Adobe Genuine Service kept, CoreSync protected, no processes killed. The v1.1.0 live run then exposed the launcher problem above; v1.2.0 is the first version expected to actually remove CC apps and has **not yet been confirmed live**.
- Acrobat was **not** registered on that device — it had been uninstalled manually beforehand — yet the `LIBR-AcrobatDC` package wrapper survived that removal. Expect the same on any device where Acrobat was removed by any route: **removing the product does not remove the Admin Console package wrapper**, so Programs and Features keeps showing an Acrobat entry. It is cosmetic, and the script leaves it alone by default.
- To clear a wrapper whose products are already gone, uninstall that one wrapper by hand (`msiexec /x {ProductCode} /qn`) rather than using `-RemovePackageWrappers`, which is all-or-nothing and would also hit `AdobeCC_SelfService`.
- Reference: Adobe, "Uninstall Creative Cloud products" (`helpx.adobe.com/enterprise/using/uninstall-creative-cloud-products.html`) for `AdobeUninstaller.exe` options and SAP codes.
