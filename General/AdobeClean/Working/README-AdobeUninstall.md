# Adobe Product Uninstall — Intune Win32 App

Removes every Adobe product from a device. Two modes:

| Mode | Invocation | Result |
| --- | --- | --- |
| **Keep Creative Cloud** *(default, validated)* | `.\Uninstall-AdobeProducts.ps1` | Every Adobe app removed; the Creative Cloud desktop app and Adobe Genuine Service stay (CC would silently reinstall AGS anyway). Users keep the launcher and can reinstall apps themselves |
| **Full wipe** | `.\Uninstall-AdobeProducts.ps1 -RemoveCreativeCloud` | The above, then the Creative Cloud desktop app itself, then `C:\ProgramData\Adobe`. Nothing Adobe is left registered |

Complements `LIB-AdobeInstallerCleanup.ps1`, which targets Acrobat installer-cache growth; this script is the general "wipe Adobe" tool.

## Contents

| File | Purpose |
| --- | --- |
| `Uninstall-AdobeProducts.ps1` | Enumerates Adobe entries in both Uninstall hives, keeps anything matching `-KeepPattern`, silently removes the rest with the right mechanism per installer type. `-RemoveCreativeCloud` / `-CleanProgramData` turn it into a full wipe |
| `Detect-AdobeUninstall.ps1` | Custom detection: sentinel `Completed=1` **and** a live re-check that no non-kept Adobe product exists. Reads `FullRemoval` so one detection script serves both modes |
| `Uninstall-AdobeCleanupApp.ps1` | Uninstall action for the Win32 app. Clears the detection sentinel only — adds and removes no Adobe product. See *Company Portal* below for why this is not the removal script |
| `AdobeUninstaller.exe` *(optional, not in repo)* | Adobe's supported bulk uninstaller. Download from **Admin Console → Packages → Tools → Adobe Uninstaller**. Drop it next to the script before packaging and it is used first for CC apps |

## How products are removed

| Installer type | How it is identified | Command used |
| --- | --- | --- |
| Creative Cloud / HyperDrive apps (Photoshop, Illustrator, InDesign, Premiere, After Effects, Lightroom, Bridge, Substance…) | `UninstallString` contains `--sapCode=` / `HDBox\` | 1. `AdobeUninstaller.exe --products=PHSP#25.0,ILST#28.0 --skipNotInstalled` if bundled. 2. Otherwise Adobe's silent engine `HDBox\Setup.exe --uninstall=1 --sapCode=… --baseVersion=… --platform=win64 --deleteUserPreferences=false`, with sapCode/version parsed from the registry string. **The registry `UninstallString` itself is never run** (see *Lessons from the first live run*) |
| MSI (Acrobat, Reader, Refresh Manager, AIR…) | `WindowsInstaller=1` or `msiexec` in `UninstallString` | `msiexec /x {ProductCode} /qn /norestart REBOOT=ReallySuppress` |
| Other EXE (Digital Editions, etc.) | everything else | `QuietUninstallString` if present, else `UninstallString /S` (best effort) |
| **Admin Console package wrappers** (`AdobeCC_SelfService`, `Adobe.CC.201902`, `LIBR-AcrobatDC`…) | MSI with `DisplayVersion = 1.0.0000` | **Skipped by default** and ignored by detection. These are package registrations, not apps; uninstalling one removes every product in that package, and a self-service package's only product is the CC desktop app. `-RemovePackageWrappers` includes them |
| Legacy CS5/CS6/early-CC (`PDApp.exe`) | `PDApp.exe` in `UninstallString` | **Skipped with WARN** — no silent mode exists; use the Creative Cloud Cleaner Tool |
| **Creative Cloud desktop app** (`-RemoveCreativeCloud` only) | `DisplayName` matches `^Adobe Creative Cloud` | `"…\Adobe\Adobe Creative Cloud\Utils\Creative Cloud Uninstaller.exe" -u`, run **last** (STEP 6). Adobe's uninstaller declines while any CC app is still installed, so the step aborts with an ERROR listing the blockers rather than pretending to succeed |
| **`C:\ProgramData\Adobe`** (`-CleanProgramData` only) | — | `takeown /F … /A /R /D Y` + `icacls … /grant *S-1-5-32-544:(OI)(CI)F /T /C /Q`, then `Remove-Item -Recurse -Force` per child (STEP 8). Ownership is required: `SLStore` and friends are SYSTEM-owned and deny delete even to Administrators |

Every uninstaller runs under a hard timeout (`-TimeoutMinutes`, default 30) and is killed if it hangs, so a stray prompt can't wedge the Intune install. `Win32_Product` is never queried (it triggers MSI self-repair on every product on the machine).

Processes are stopped by **path**: anything running from `Program Files\Adobe\*` or `Program Files (x86)\Adobe\*` that does not match a keep pattern or the built-in `$ProtectedPathPattern` (`Adobe Creative Cloud`, `Creative Cloud Experience`, `Adobe Sync` [CoreSync], `Adobe Desktop Common`, `AdobeGCClient`, `Adobe\Common`). Creative Cloud's runtime under `Common Files\Adobe\*` is never in scope. The same protected list guards `-RemoveLeftoverFolders`.

Under `-RemoveCreativeCloud` that protection is **still active through STEP 3–5** — killing CoreSync or `AdobeGCClient` mid-run breaks the app uninstalls. STEP 6 stops the CC services (`AdobeUpdateService`, `AGSService`, `AGMService`, `AdobeARMservice`) and processes itself, runs the uninstaller, and only releases the protected list once the CC registry entry is confirmed gone — so `-RemoveLeftoverFolders` and the `ProgramData` sweep can then take those folders.

## Parameters

| Parameter | Default | Notes |
| --- | --- | --- |
| `-KeepPattern` | `'Adobe Creative Cloud','Adobe Genuine Service'` | Regex list matched against `DisplayName`. Add `'Adobe Acrobat'` to keep Acrobat, etc. Keep `Detect-AdobeUninstall.ps1` in sync. Cleared to `@()` by `-RemoveCreativeCloud` unless you pass it explicitly |
| `-RemoveCreativeCloud` | off | Also remove the CC desktop app (STEP 6, last). **Implies an empty `-KeepPattern` and `-CleanProgramData`.** Deactivates licensing — users sign in again after any reinstall. Stamps `FullRemoval=1` on the sentinel |
| `-CleanProgramData` | off (on when `-RemoveCreativeCloud`) | Clears `C:\ProgramData\Adobe`. Suppress with `-CleanProgramData:$false`. If a CC desktop app is still installed when this runs, the licensing children (`SLStore`, `SLCache`, `AAMUpdater`, `OOBE`, `caps`, `Adobe Desktop Common`, `ARM`, `Adobe Notification Client`) are **preserved** so the retained install is not deactivated |
| `-RemoveUserPreferences` | off | Passes `--deleteUserPreferences=true` to the CC app uninstaller |
| `-RemovePackageWrappers` | off | Also `msiexec /x` the Admin Console package wrapper MSIs. **A self-service wrapper removes the CC desktop app** — only use on devices where the wrappers are known to contain apps only |
| `-RemoveLeftoverFolders` | off | Deletes orphan folders under `Program Files\Adobe` / `(x86)` that no remaining product owns. Never touches `Common Files\Adobe` |
| `-AdobeUninstallerPath` | `<script dir>\AdobeUninstaller.exe` | Override location of Adobe's tool |
| `-TimeoutMinutes` | 30 | Per-uninstaller kill timer |
| *(baseVersion resolution)* | automatic | `application.json` → `major.0` → `major.0.0` → exact → `major.minor[.0]` → descending minors → descending majors (`M.0`, `M.0.0`), capped at 48. Each miss costs ~1 s and exit 135 |
| `-WhatIf` | | Inventory + plan only, no changes, no sentinel |

## Outputs

- Log: `C:\ProgramData\LIBR\Logs\AdobeUninstall-<yyyyMMdd-HHmmss>.log`
- Sentinel: `HKLM\SOFTWARE\LIBR\AdobeUninstall` → `Completed` (DWORD 1/0), `Remaining`, `ScriptVersion`, `LastRun`, `LastLog`, `FullRemoval` (DWORD 1 when run with `-RemoveCreativeCloud`)
- Exit codes: `0` all removed · `3010` all removed, reboot required · `1` not admin or products remain

## Package

```powershell
# Optional: copy AdobeUninstaller.exe into General\AdobeClean first
IntuneWinAppUtil.exe -c "<repo>\General\AdobeClean" -s Uninstall-AdobeProducts.ps1 -o "<output-folder>"
```

`-c` bundles the folder **recursively**, so the legacy scripts in `Old\` end up inside the `.intunewin` too. Harmless but untidy — point `-c` at a staging copy holding only the three current scripts (plus `AdobeUninstaller.exe`) if you want a clean package.

With the PowerShell script installer, both scripts are stored as app **metadata** — they can be edited in the portal without repackaging. Sync any portal hot-fix back to this repo.

## Intune app — Method A (command line, preferred: script is versioned inside the package)

| Setting | Value |
| --- | --- |
| Install command | `%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File Uninstall-AdobeProducts.ps1` |
| Uninstall command | `%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File Uninstall-AdobeCleanupApp.ps1` *(clears the sentinel; see Company Portal below for why this must not be the removal script)* |
| Install behavior | **System** |
| **Maximum allowed install time** | **240 minutes** (default is 60 — see *Runtime* below; the app is marked failed at the limit even while it is still working) |
| Device restart behavior | Determine behavior based on return codes |
| Return codes | `0` Success · `3010` Soft reboot · `1` Failed |
| Detection | Custom script → `Detect-AdobeUninstall.ps1` (Run as 32-bit: No) — or a registry rule: `HKLM\SOFTWARE\LIBR\AdobeUninstall`, value `Completed`, Integer equals `1` |

Add `-RemoveLeftoverFolders` / `-KeepPattern ...` to the install command as needed. If both variants of the app exist, give them distinct sentinel keys by editing `$SentinelKey` (and the detection script).

### Full-wipe variant (removes Creative Cloud too)

**Method A** — same package, different install command:

```
%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File Uninstall-AdobeProducts.ps1 -RemoveCreativeCloud -RemoveLeftoverFolders
```

**Method B (paste)** — there is no command line, so the switch cannot be passed. Edit one line in `begin{}` before pasting:

```powershell
$ForceFullRemoval = $true    # was $false
```

That is the *only* edit needed: it sets `-RemoveCreativeCloud`, which in turn implies `-KeepPattern @()` and `-CleanProgramData`. Keep the repo copy at `$false` and flip it in the portal paste for the full-wipe app, so the default app can never be turned into a wipe by accident. Any other switch can be reached the same way by changing its default in the `param()` block.

`-RemoveCreativeCloud` implies `-KeepPattern @()` and `-CleanProgramData`, and stamps `FullRemoval=1` on the sentinel so `Detect-AdobeUninstall.ps1` drops its keep list automatically — no edit to the detection script needed.

> [!caution] Re-install loop
> Intune reinstalls a Win32 app whenever its detection later goes false. In keep-CC mode that is the desired behaviour (someone reinstalls Acrobat → it gets removed again). With `FullRemoval=1` the keep list is dropped, so **a user who reinstalls Creative Cloud from adobe.com will have it silently wiped again** at the next detection cycle. That is the intended outcome on a locked-down lab machine and a support ticket anywhere else. Scope the assignment accordingly.

**Ship this one as Required to a device group, never as Available in Company Portal.** It deactivates Adobe licensing on the device and leaves the user with no way to reinstall anything; that is a decision for the person assigning the app, not a self-service button. Name it so it cannot be confused with the default app, e.g. *Remove ALL Adobe Software (including Creative Cloud)*.

If you deploy both variants to the same fleet, give them **different sentinel keys** (edit `$SentinelKey` in both the removal and detection scripts) — otherwise whichever ran last owns the detection state for both apps.

## Company Portal (self-service) — assigning this as **Available**

Users can run this themselves from Company Portal. It works well, with one trap and three hazards.

**The trap: do not use the removal script as the Uninstall action.** Intune verifies an uninstall by re-running the detection rule and expecting **not-detected**. The removal script rewrites the sentinel and leaves the machine clean, so detection stays true and the uninstall is reported as **failed** every time — and the app sticks at "Installed". Point Uninstall at `Uninstall-AdobeCleanupApp.ps1`, which deletes `HKLM\SOFTWARE\LIBR\AdobeUninstall` and nothing else. Detection then goes false and the uninstall succeeds.

That also gives users a **re-run path**. Once the removal succeeds, detection blocks the Install button; Uninstall → Install lets them run it again (e.g. apps were reinstalled and left a partial state). Removing the sentinel never puts an Adobe app back.

| Setting | Value |
| --- | --- |
| Installer type | **PowerShell script** |
| Install script | `Uninstall-AdobeProducts.ps1` |
| Uninstall script | **`Uninstall-AdobeCleanupApp.ps1`** (not the removal script) |
| Run script as 32-bit | **No** (the removal script aborts in a 32-bit host) |
| Install behavior | **System** |
| Max allowed install time | **240** minutes |
| Device restart behavior | Determine behavior based on return codes |
| Return codes | `0` Success · `3010` Soft reboot · `1` Failed |
| Detection | Custom script → `Detect-AdobeUninstall.ps1` (Run as 32-bit: **No**) |
| Assignment | **Available for enrolled devices** → user group |

**Self-service is for the keep-CC mode only** — the full wipe belongs in a Required assignment (see *Full-wipe variant* above).

**Name and description matter — Company Portal gives no confirmation prompt.** Name it for what it does, e.g. *Remove Adobe Creative Cloud Apps (keeps Creative Cloud)*. Put this in the description, because it is the only warning a user sees:

> Removes Photoshop, Illustrator, InDesign, Premiere Pro and all other Adobe apps from this computer. The Creative Cloud desktop app stays, so you can reinstall any app you still need. **Close all Adobe apps and save your work before starting — anything still open will be closed without warning.** Takes about 15 minutes.

Three hazards to weigh before opening it to self-service:

1. **Unsaved work is destroyed.** Step 2 force-kills everything running from the Adobe program folders. Running as SYSTEM there is no prompt and no way to cancel. The description above is the only mitigation.
2. **~15 minutes of "Installing".** Company Portal shows no progress detail for that whole time.
3. **A partial failure surfaces as "Failed"** with no user-facing explanation. The reason is in `C:\ProgramData\LIBR\Logs\AdobeUninstall-*.log`.

State on a machine that never had Adobe apps: detection is false (no sentinel), so the app still offers Install; running it removes nothing, writes the sentinel and reports success. Harmless.

## Intune app — Method B (PowerShell script installer, paste)

**This is the method in use on the LIBR fleet.** Set **Installer type = PowerShell script** and paste `Uninstall-AdobeProducts.ps1` as the install script and `Uninstall-AdobeCleanupApp.ps1` as the uninstall script.

Both are stored as app **metadata** and can be edited in the portal without repackaging — sync any portal hot-fix back to this repo. The script locates `AdobeUninstaller.exe` via the current directory when `$PSScriptRoot` is empty, so bundling it in the `.intunewin` still works.

> [!important] Watch the size
> v1.5.0 briefly reached 55 KB, over the 50 KB paste limit. The comment-based help was condensed and the changelog moved into this file to bring it back under. See *Keeping the script pasteable* below and check the size before every paste.

**A pasted script receives no command line.** Every parameter therefore takes its default. For the default keep-CC behaviour that is exactly right — paste and go. For the full wipe, set `$ForceFullRemoval = $true` in `begin{}` (see *Full-wipe variant* above); do not try to add switches to a command line that does not exist.

## Lessons from the first live run (2026-09-01, v1.1.0, `LIBRWKSPC010189`)

The first real run reported 16 removals in 32 seconds and removed nothing. Every app's registry `UninstallString` on current CC builds looks like:

```
"…\HDBox\Uninstaller.exe" --uninstall=1 --sapCode=PHSP --productVersion=27.10 --productPlatform=win64 --productAdobeCode={…} --productName="Photoshop" --mode=2
```

That is the **Programs and Features launcher**, not an uninstaller. It hands the job to the Creative Cloud desktop app (hence the sign-in window that popped for every app), then exits 0 after ~2 seconds. Under SYSTEM there is no desktop to hand off to, so it silently does nothing. v1.2.0 therefore:

- Ignores the registry command and builds Adobe's documented silent command against `HDBox\Setup.exe`. Note that HDBox contains **both** `Setup.exe` (~850 KB, the HyperDrive engine, macOS twin is `HDBox/Setup`) and `Set-up.exe` (~14 MB, the Creative Cloud installer bootstrapper). The script prefers `Setup.exe` and logs which one it used.
- **Credits a removal only when the product's Uninstall key has disappeared.** Exit codes from Adobe launchers are not trusted. Each uninstall also logs its duration; ~2 s means nothing happened.
- Counts shared components (e.g. `UXP WebView Support`) that disappear as a side effect of another app's uninstall, instead of skipping them silently and leaving the tally short.

Before re-running on that device, dismiss any Creative Cloud sign-in / uninstall dialogs the v1.1.0 run left open, otherwise the HD engine may report another instance is running.

**Second live run (v1.2.2)** used the right engine and removed exactly one app: Character Animator 26.0, in 154 s. The other 15 were declined in ~1 s each. The difference: Character Animator had never been updated, so its current version *was* its base version. `--baseVersion` means the version of the **original install** (Photoshop 27.0), not the current patched version the registry reports (27.10). v1.3.0 tries `major.0` → exact → `major.minor` per app and stops when the Uninstall key disappears; a wrong candidate costs one second and exit 135. If every candidate fails for an app, `AdobeUninstaller.exe --list` (Admin Console tool) prints the authoritative sapCode#baseVersion pairs.

**Third live run (v1.3.0)** removed 12 of 14 in 14.5 minutes. `major.0` was correct for almost every app (Photoshop 27.10 → `27.0`, Illustrator 30.8.1 → `30.0`). Two refused every candidate with exit 135: **Bridge** (KBRG 16.0.6) and **Lightroom** (LRCC 9.5.1). Cause: Adobe also publishes **three-part** base versions (e.g. Bridge has historically used `12.0.0`), and v1.3.0 only tried two-part forms plus the exact version. v1.3.1 adds `major.0.0`, `major.minor.0`, and a descending-minor sweep, and — better — reads the real value from the app's own `application.json` when it can find one.

**Bridge and Lightroom needed a major-version sweep (v1.3.3).** Diagnostics on `LIBRWKSPC010189` showed both still installed (`C:\Program Files\Adobe\Adobe Bridge 2026`, `…\Adobe Lightroom CC`), with **no `application.json` anywhere** and registry key names `KBRG_16_0_6` / `LRCC_9_5_1` that carry the *product* version only. The cause is that apps on a rolling release train keep the base version of their original release for years — Adobe documents Bridge as base **12.0.0** while it ships 16.x. Sweeping minors inside major 16 could never reach it. v1.3.3 walks majors downward too (`16.0`, `16.0.0`, `15.0`, … `12.0`, `12.0.0`, …), capped at 48 candidates, ~1 s per miss. Apps whose base is `major.0` (nearly all of them) still succeed on the first attempt.

**Resolved (v1.3.4 run, 22:09).** Both stragglers removed, and the two base versions were:

| App | SAP code | Installed version | Actual base version | Found by |
| --- | --- | --- | --- | --- |
| Bridge 2026 | `KBRG` | 16.0.6 | **16.0.0** | 2nd candidate (`major.0.0`) |
| Lightroom | `LRCC` | 9.5.1 | **1.0** | 22nd candidate (descending major sweep) |

Lightroom proves the rolling-train case: it ships 9.x on a base version from its original release. v1.4.0 seeds a `$KnownBaseVersion` table with `LRCC = 1.0` so other devices skip the ~35 s sweep. Bridge needs no entry — `major.0.0` is already the second candidate. **Add to that table whenever a sweep discovers a new value**; the log line `baseVersion X accepted` names it.

**Reading the exit codes.** `135` means "no product installed at that sapCode + baseVersion" — the guess was wrong, move on. **Any other non-zero code means the baseVersion was recognised** and the uninstall itself failed; that is the value worth investigating, and v1.3.4 logs it explicitly rather than burying it in the sweep. On `LIBRWKSPC010189`, `KBRG` + `12.0.0` returned **exit 1** where 16.0/16.0.6 returned 135. That was a red herring — the real base was 16.0.0. Treat a non-135 code as *worth investigating*, not as proof the base version is right.

Adobe records the reason in its installer logs:

```
%ProgramFiles(x86)%\Common Files\Adobe\Installers\*.log
%TEMP%\CreativeCloud\ACC\*.log
```

**`application.json` is the authoritative local source when it exists** (it did not on this device). Adobe's own guidance for admins hitting error 135 is to read `BaseVersion` out of `Build\HD\<sapCode>\Application.json` in the package source; installed apps carry the same file. v1.3.1 searches up to 3 levels under the product's `InstallLocation`, and logs the path and value when it finds one.

Also fixed in v1.3.0: exit codes were logging blank (and being treated as 0) because `Start-Process -PassThru` returns a null `ExitCode` after `WaitForExit(timeout)` unless the process handle is touched first. Real codes are now logged.

## Runtime — read before assigning

Creative Cloud apps are uninstalled **sequentially**. Measured on `LIBRWKSPC010189`: 18–120 s per app, **14.5 minutes for 14 apps**. Budget more on slower disks, plus ~1 s per wrong baseVersion candidate on apps not in the known-base table. A fully loaded device (18 targets measured on `LIBRWKSPC010189`) can therefore run **30–130 minutes**. Two consequences:

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

Full-wipe checks:

```powershell
# Dry run of the full wipe - CC and ProgramData steps are logged as "What if:"
.\Uninstall-AdobeProducts.ps1 -RemoveCreativeCloud -WhatIf

# Creative Cloud desktop app gone?
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
  Where-Object DisplayName -match '^Adobe Creative Cloud' |
  Select-Object DisplayName, DisplayVersion

# ProgramData cleared? (empty = clean; SLStore etc. present = CC was kept)
Get-ChildItem C:\ProgramData\Adobe -Force -ErrorAction SilentlyContinue | Select-Object Name

# Anything Adobe still running
Get-Process | Where-Object { $_.Path -match '\\Adobe\\' } | Select-Object ProcessName, Path

# Mode recorded by the last run
(Get-ItemProperty HKLM:\SOFTWARE\LIBR\AdobeUninstall).FullRemoval   # 1 = full wipe
```

## Changelog

Kept here rather than in the script header: the script is pasted into Intune's PowerShell script installer box, which has a **50 KB** limit, and the changelog was 5 KB of it.

**v1.5.0** — Added `-RemoveCreativeCloud`: removes the CC desktop app itself in a new final product step (STEP 6), after every CC app, because Adobe's uninstaller declines otherwise. Implies an empty `-KeepPattern` and `-CleanProgramData`. CC runtime path protection is released only once the desktop app is confirmed gone.
- Added `-CleanProgramData`: `takeown` + `icacls`, then clears `C:\ProgramData\Adobe` (STEP 8). Preserves the licensing children (`SLStore`, `SLCache`, `AAMUpdater`, `OOBE`, `caps`, …) when the CC desktop app is being kept, so a retained install stays activated.
- Sentinel gained `FullRemoval`; `Detect-AdobeUninstall.ps1` v1.2.0 reads it so one detection script serves both modes.
- **Comment-based help condensed and the changelog moved here** to bring the file back under the 50 KB paste limit (it had reached 55 KB). Load-bearing explanations stayed at their code sites.

**v1.4.0** — VALIDATED END TO END on LIBRWKSPC010189 (2026-09-01): all 15 CC apps removed, CC desktop app + Adobe Genuine Service kept, sentinel Completed=1.
- Added $KnownBaseVersion table seeded with LRCC=1.0 (Lightroom ships 9.x on a base of 1.0; the blind sweep needed 22 attempts). Bridge needed no entry - its base is major.0.0 (16.0.0), which is already the second candidate.
**v1.3.4** — Sweep now distinguishes 135 (wrong baseVersion) from any other non-zero code (baseVersion recognised, uninstall itself failed) and reports the recognised values plus where Adobe logs them.
**v1.3.3** — baseVersion sweep now walks MAJOR versions down as well as minors. Bridge/Lightroom sit on a rolling train and keep an old base version (Adobe documents Bridge as 12.0.0) while shipping 16.x/9.x, so the correct value was unreachable. Capped at 48 candidates (~48 s worst case).
- Program Files\Adobe\Common protected from -RemoveLeftoverFolders.
**v1.3.2** — application.json lookup no longer depends on InstallLocation (empty for most HD apps): also searches Program Files\Adobe folders matching the product name and per-sapCode HD staging paths, and only trusts a file that names the sapCode.
**v1.3.1** — baseVersion now read from the app's own application.json when present (authoritative); candidate list extended with 3-part forms (16.0.0) and a descending-minor sweep. Bridge/Lightroom failed at 135 because only 2-part forms were tried.
- Products removed as a side effect of another app's uninstall (shared components like UXP WebView Support) are now counted and logged instead of silently skipped.
**v1.3.0** — FIX: --baseVersion must be the ORIGINAL install version (27.0), not the current updated version the registry reports (27.10). Only never-updated apps worked. Now tries major.0 -> exact -> major.minor until the Uninstall key disappears.
- FIX: exit codes were always $null (Start-Process handle quirk), coerced to 0 in logs. Handle is now cached; real codes logged.
**v1.2.2** — HD engine probe now prefers HDBox\Setup.exe (the engine) over Set-up.exe (the CC installer bootstrapper) - both exist on current builds and the wrong one was being picked first.
**v1.2.1** — Abort when run from a 32-bit host on 64-bit Windows (registry redirection hides 64-bit products); log host bitness in header.
**v1.2.0** — FIX: per-app CC uninstall ran the registry UninstallString (HDBox\Uninstaller.exe --mode=2), which is a GUI launcher that delegates to the CC desktop app (sign-in popup) and exits 0 without removing anything. Now builds the documented silent command against HDBox\Set-up.exe / Setup.exe from sapCode + version parsed out of the registry string.
- FIX: success is verified by the product's Uninstall key disappearing, not by exit code. Per-uninstall duration logged.
**v1.1.1** — Inventory tag now shows SKIP (not REMOVE) for untargeted package wrappers; type column widened for 'Package'.
- Options line records -RemovePackageWrappers and the timeout; summary reports elapsed minutes (watch Intune's install timeout).
**v1.1.0** — Logging no longer suppressed by -WhatIf (Add-Content -WhatIf:$false).
- Creative Cloud runtime processes/folders (CoreSync under "Adobe Sync", "Adobe Creative Cloud Experience", HDBox) are protected by $ProtectedPathPattern regardless of -KeepPattern.
- Admin Console package wrapper MSIs classified as 'Package' and skipped by default (-RemovePackageWrappers to include).
- WhatIf summary wording ("Would remove" instead of "Still installed").
**v1.0.0** — Initial release.

## Keeping the script pasteable

The Intune PowerShell script installer box takes **50 KB**. `Uninstall-AdobeProducts.ps1` currently sits at **49,781 bytes (48.6 KB)** — under the limit on either reading of "50 KB" (50,000 or 51,200 bytes), with ~219 bytes of headroom. Check before every paste:

```powershell
'{0:n0} bytes ({1:n1} KB)' -f (Get-Item .\Uninstall-AdobeProducts.ps1).Length, ((Get-Item .\Uninstall-AdobeProducts.ps1).Length / 1KB)
```

If an edit pushes it over, take the space out of the comment-based help and move the prose into this file — **not** out of the inline comments at the code sites. Every one of those records a live-run failure and is the reason the next editor won't reintroduce it.

## Caveats / security notes

- **Acrobat is removed** unless you add `'Adobe Acrobat'` to `-KeepPattern`. On the LIBR fleet Acrobat is owned by DIT via Patch My PC; coordinate before mass-deploying or PMPC will just put it back.
- Creative Cloud will show removed apps as "Install" again — expected. Users with a CC entitlement can reinstall; kiosk/lab images should have CC self-service restricted via the Admin Console package options.
- **`-RemoveCreativeCloud` deactivates the device.** Clearing `C:\ProgramData\Adobe` destroys the local licensing/activation state (`SLStore`, `caps`). Reinstalling requires a network trip and a fresh sign-in. The script preserves those children when a CC install survives, but there is no undo once they are gone.
- **`takeown` + `icacls` on `C:\ProgramData\Adobe` is a detectable pattern.** CrowdStrike Falcon flags ownership seizure followed by recursive deletion as ransomware-adjacent behaviour. Running it under the Intune Management Extension (`IntuneManagementExtension.exe` → `powershell.exe` as SYSTEM) is the mitigating context; if Falcon raises detections during the pilot, ask the security team to allowlist that parent-process chain for this script rather than turning the step off. Scope is limited to `C:\ProgramData\Adobe` and its children — the script never walks a parent path.
- **The CC uninstaller cannot be forced.** If any CC app survives STEP 3, STEP 6 logs the blockers and exits 1 rather than running the uninstaller into a guaranteed failure. Fix the app removal (usually a baseVersion) and re-run; there is no `-Force`.
- **Keep-CC mode is validated as SYSTEM** — run successfully from Company Portal as an Available self-service app. That closes the v1.1.0 concern (a launcher handing off to a desktop SYSTEM does not have) for STEPS 1–5.
- **The full wipe is NOT validated as SYSTEM.** `Creative Cloud Uninstaller.exe` is a different binary from the HD engine and has never run headless here. Pilot `-RemoveCreativeCloud` as **Required** on one device and read the log before assigning it anywhere else. The script judges success by the registry key disappearing, so a silent no-op surfaces as a failure rather than a false success — but it would still be a failure.
- User data in `AppData\*\Adobe` is **not** touched (the CC desktop app shares those folders). Use `Clean-Adobe.ps1` only when CC is also being removed.
- CrowdStrike/Rapid7: mass process kills + `msiexec /x` from SYSTEM are normal Intune behavior and match the existing cleanup app's footprint; no new detections expected.
- `UXP WebView Support` is an HD shared runtime used by CC apps (not by the CC desktop app itself) and is removed with them; CC reinstalls it on demand.
- Verified on `LIBRWKSPC010189` (2026-09-01, `-WhatIf`, v1.1.1): 18 targets (16 HD apps + 2 MSIs), 3 package wrappers skipped, CC desktop app + Adobe Genuine Service kept, CoreSync protected, no processes killed. The v1.1.0 live run then exposed the launcher problem above; **Fully validated end to end on `LIBRWKSPC010189` (2026-09-01, v1.3.4):** all 15 Creative Cloud apps removed across three runs, Creative Cloud desktop app and Adobe Genuine Service kept and functional, `Completed=1` sentinel written, script exit 0. Never validated under SYSTEM/Intune — do that on one pilot device before assigning broadly.
- Acrobat was **not** registered on that device — it had been uninstalled manually beforehand — yet the `LIBR-AcrobatDC` package wrapper survived that removal. Expect the same on any device where Acrobat was removed by any route: **removing the product does not remove the Admin Console package wrapper**, so Programs and Features keeps showing an Acrobat entry. It is cosmetic, and the script leaves it alone by default.
- To clear a wrapper whose products are already gone, uninstall that one wrapper by hand (`msiexec /x {ProductCode} /qn`) rather than using `-RemovePackageWrappers`, which is all-or-nothing and would also hit `AdobeCC_SelfService`.
- Reference: Adobe, "Uninstall Creative Cloud products" (`helpx.adobe.com/enterprise/using/uninstall-creative-cloud-products.html`) for `AdobeUninstaller.exe` options and SAP codes.
