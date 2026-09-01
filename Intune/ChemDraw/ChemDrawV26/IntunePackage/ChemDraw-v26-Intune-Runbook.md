# ChemDraw 26 - Single-Package Intune Deployment Runbook

## Table of Contents

- [[#Deployment Design]]
- [[#Combined Package Layout]]
- [[#Build the Intunewin]]
- [[#Configure the Intune Win32 App]]
- [[#Native PowerShell Install and Uninstall]]
- [[#Installation Sequence]]
- [[#Detection Rule]]
- [[#Pilot and Verification]]
- [[#Security and Troubleshooting]]

---

## Deployment Design
> [[#Table of Contents|↑ Back to TOC]]

Deploy ChemDraw 26 and ChemDraw Applications 26 as one Win32 app. A single PowerShell installer controls the sequence:

```text
Main ChemDraw 26
        ↓
ChemDraw Applications 26
        ↓
Bulk activation
        ↓
Final Intune detection sentinel
```

The package uses Intune's native PowerShell installer fields for both installation and uninstallation. No PowerShell command line is required in the Intune Program settings.

Current wrapper revision: `2.0.1`. This revision detects an installed WebView2 Evergreen Runtime before attempting prerequisite installation.

---

## Combined Package Layout
> [[#Table of Contents|↑ Back to TOC]]

```text
Combined\
├── Build-ChemDraw26-CombinedIntuneWin.ps1
├── Output\
│   └── ChemDraw26-Combined.intunewin
└── Source\
    ├── PackageMarker.txt
    ├── Install-ChemDraw26-IntuneNative.ps1
    ├── Uninstall-ChemDraw26-IntuneNative.ps1
    ├── Detect-ChemDraw26-Combined.ps1
    ├── Revvity\
    │   ├── Activation\
    │   ├── ChemDraw\
    │   └── ChemDrawApplications\
    └── ThirdParty\
```

`PackageMarker.txt` is the required `-s` placeholder for the Content Prep Tool. The PowerShell scripts locate this marker to identify the unpacked payload directory.

---

## Build the Intunewin
> [[#Table of Contents|↑ Back to TOC]]

Download Microsoft's signed [Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool), then run:

```powershell
.\Combined\Build-ChemDraw26-CombinedIntuneWin.ps1 `
    -IntuneWinAppUtilPath 'C:\Tools\IntuneWinAppUtil.exe'
```

Equivalent manual packaging command:

```powershell
IntuneWinAppUtil.exe `
    -c '.\Combined\Source' `
    -s 'PackageMarker.txt' `
    -o '.\Combined\Output' `
    -q
```

The build wrapper renames the generated archive to `ChemDraw26-Combined.intunewin`.

---

## Configure the Intune Win32 App
> [[#Table of Contents|↑ Back to TOC]]

| Setting | Value |
|---|---|
| App type | Windows app (Win32) |
| Package | `Combined\Output\ChemDraw26-Combined.intunewin` |
| Name | `Revvity ChemDraw 26.0.0 + Applications` |
| Install behavior | System |
| Architecture | 64-bit Windows |
| Device restart behavior | Determine behavior based on return codes |
| Return code 0 | Success |
| Return code 1 | Failed |
| Return code 3010 | Soft reboot |

Do not configure a traditional `powershell.exe -File` install or uninstall command. Use the native PowerShell installer fields described below.

---

## Native PowerShell Install and Uninstall
> [[#Table of Contents|↑ Back to TOC]]

For the **Install PowerShell script**, upload or paste:

```text
Combined\Source\Install-ChemDraw26-IntuneNative.ps1
```

For the **Uninstall PowerShell script**, upload or paste:

```text
Combined\Source\Uninstall-ChemDraw26-IntuneNative.ps1
```

Both scripts support the two Intune execution models:

- When called with `-File`, they use `$PSScriptRoot` if `PackageMarker.txt` is present.
- When pasted or staged separately by Intune, they use the current working directory containing the unpacked package.

Both scripts are below Intune's 50 KB PowerShell installer-script limit.

---

## Installation Sequence
> [[#Table of Contents|↑ Back to TOC]]

The combined installer performs these actions:

1. Validates the complete payload and activation-file format.
2. Removes incompatible ChemDraw versions 22 through 25.
3. Installs .NET Framework 4.8 when required.
4. Installs the x86 and x64 Visual C++ redistributables.
5. Detects WebView2 from Microsoft's per-machine runtime registry entry and installs it only when missing.
6. Installs `Revvity_ChemDraw_26.0.0_x64.msi`.
7. Installs `Revvity_ChemDraw_Applications_26.0.0_x64.msi`.
8. Installs the x86 Applications MSI when 32-bit Office is detected.
9. Runs `Activate.exe 26.0 IsInstaller Silent`.
10. Writes the detection sentinel only after activation succeeds.

Python support is disabled by default to avoid changing an independently managed endpoint runtime. The vendor Python payloads remain bundled for future use.

The uninstall script runs in reverse order, attempts best-effort license deactivation, and then removes:

1. Applications x86 MSI
2. Applications x64 MSI
3. Main ChemDraw x64 MSI

---

## Detection Rule
> [[#Table of Contents|↑ Back to TOC]]

Use a custom detection script:

```text
Combined\Source\Detect-ChemDraw26-Combined.ps1
```

Detection returns exit code 0 only when:

- The main ChemDraw MSI is installed.
- The Applications x64 MSI is installed.
- The Applications x86 MSI is installed when required.
- The post-activation registry sentinel is present.

Detection output remains below the Intune 2048-character limit.

---

## Pilot and Verification
> [[#Table of Contents|↑ Back to TOC]]

1. Pilot on a device currently running ChemDraw 2025.
2. Confirm the previous version is removed.
3. Confirm both v26 products appear in installed applications.
4. Launch ChemDraw as a standard user.
5. Confirm no activation dialog is displayed.
6. Review deployment logs:

   ```powershell
   Get-ChildItem 'C:\ProgramData\UMDLibraries\ChemDraw\Logs' |
       Sort-Object LastWriteTime -Descending
   ```

7. Confirm the detection script returns 0:

   ```powershell
   powershell.exe -ExecutionPolicy Bypass -NoProfile `
       -File .\Detect-ChemDraw26-Combined.ps1
   $LASTEXITCODE
   ```

---

## Security and Troubleshooting
> [[#Table of Contents|↑ Back to TOC]]

- Restrict access to `Combined\Source\Revvity\Activation\Activate.ini`; it contains the institutional activation ID.
- The activation ID is not printed in scripts, logs, documentation, or the package manifest.
- Activation requires outbound TCP 443 access to `revvitysignals.compliance.flexnetoperations.com`.
- Logs and MSI verbose logs remain under `C:\ProgramData\UMDLibraries\ChemDraw\Logs`.
- WebView2 installer failures are accepted only when the wrapper confirms that a valid per-machine Evergreen Runtime is registered after the attempt.
- Do not create broad CrowdStrike exclusions. The vendor MSI and activation files have valid Revvity signatures.
- If deactivation fails, obsolete the endpoint in the Revvity Download Center to recover the license seat.
- The previous two-app and incomplete builds are retained under `Superseded` for audit purposes and must not be deployed.
