# UMD Libraries Per-Device Sign-In Background

## Table of Contents

- [[#Outcome]]
- [[#Package Layout]]
- [[#Build the Intune Package]]
- [[#Configure the Intune Win32 App]]
- [[#Pilot and Verify]]
- [[#Operational Notes]]

---

## Outcome

> [[#Table of Contents|↑ Back to TOC]]

This Win32 app generates a **per-device** Windows lock-screen/sign-in image using the bundled [PowerBGInfo](https://github.com/EvotecIT/PowerBGInfo) module. It recreates the guidance from the reference image:

```text
Logging ON? FOLLOW INSTRUCTIONS BELOW.
User name: Directory ID (your email address without @umd.edu)
Password: Password you use for logging into ELMS
Visitors: Check at the desk to obtain a temporary Guest Account
Computer Name: <device hostname>
```

The generated image has a Windows-blue background, left-aligned guidance, and a bottom-centred computer name. The installer explicitly starts with a blank canvas so PowerBGInfo cannot inherit the existing desktop wallpaper. The device hostname is rendered locally during installation, so no shared static image or external web host is required.

The package pins PowerBGInfo **2.0.2** as `Source\PowerBGInfo.2.0.2.zip`. It is the unmodified PowerShell Gallery package, renamed because Windows PowerShell 5.1 only accepts `.zip` with `Expand-Archive`. The installer validates its SHA-256 hash and expands it under `C:\ProgramData\UMDLibraries\LibrarySignInBackground\Modules` before importing it. Bundling the module as one archive prevents partial module payloads. Endpoints do not use `Install-Module` or download code during installation.

---

## Package Layout

> [[#Table of Contents|↑ Back to TOC]]

```text
LibrarySignInBackground/
├── Intune/
│   └── Detect-LibrarySignInBackground.ps1
├── Source/
│   ├── Install-LibrarySignInBackground.cmd
│   ├── Install-LibrarySignInBackground.ps1
│   ├── Package.placeholder
│   ├── PowerBGInfo.2.0.2.zip          # Pinned MIT-licensed dependency
│   ├── Uninstall-LibrarySignInBackground.cmd
│   └── Uninstall-LibrarySignInBackground.ps1
└── README.md
```

Generated files and deployment logs remain on the endpoint at:

```text
C:\ProgramData\UMDLibraries\LibrarySignInBackground
```

---

## Build the Intune Package

> [[#Table of Contents|↑ Back to TOC]]

From the repository root, package the entire `Source` folder. The `-s` argument is deliberately a harmless placeholder; PowerShell performs the installation while all companion files remain bundled in the `.intunewin` file.

```powershell
$packageRoot = Join-Path (Get-Location) 'Intune\LibrarySignInBackground'
$outputRoot = Join-Path $packageRoot 'Output'
New-Item -Path $outputRoot -ItemType Directory -Force | Out-Null

& 'C:\Tools\IntuneWinAppUtil.exe' `
    -c (Join-Path $packageRoot 'Source') `
    -s 'Package.placeholder' `
    -o $outputRoot `
    -q
```

---

## Configure the Intune Win32 App

> [[#Table of Contents|↑ Back to TOC]]

Create a **Windows app (Win32)** and upload the generated package.

| Setting | Value |
| --- | --- |
| Name | `UMD Libraries - Sign-In Background` |
| Install behavior | `System` |
| App version | `1.0.3` |
| Restart behavior | `No specific action` |
| Install command | `Install-LibrarySignInBackground.cmd` |
| Uninstall command | `Uninstall-LibrarySignInBackground.cmd` |
| Detection | Custom script: `Intune\Detect-LibrarySignInBackground.ps1` |

Use the command-line installer above (**Method A**) for the pilot. The CMD wrapper deliberately starts 64-bit Windows PowerShell and the installer expands the pinned module archive locally. Intune also supports the native PowerShell script-installer workflow, but use it only after this package succeeds with the command-line method in your tenant.

Assign it to a small **device** pilot group first. Do not assign a Settings Catalog or custom OMA-URI lock-screen-image policy to the same devices; multiple policy owners can overwrite each other.

Also confirm that no profile sets `HKLM\SOFTWARE\Policies\Microsoft\Windows\System\DisableLogonBackgroundImage` to `1`. That policy suppresses the picture on the sign-in screen. This package deliberately reports a failure rather than changing a setting owned by another profile.

---

## Pilot and Verify

> [[#Table of Contents|↑ Back to TOC]]

After Intune reports success, lock the device or sign out and confirm the information is visible. A reboot can help clear any cached sign-in background on a newly configured device.

Run these in elevated 64-bit Windows PowerShell for a diagnostic check:

```powershell
& '.\Intune\LibrarySignInBackground\Intune\Detect-LibrarySignInBackground.ps1'
$LASTEXITCODE

Get-ItemProperty 'HKLM:\SOFTWARE\UMDLibraries\Intune\LibrarySignInBackground'
Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name LockScreenImage
Get-Content 'C:\ProgramData\UMDLibraries\LibrarySignInBackground\Install-LibrarySignInBackground.log' -Tail 100
```

Expected detection output:

```text
UMD Libraries sign-in background 1.0.3 detected
0
```

---

## Operational Notes

> [[#Table of Contents|↑ Back to TOC]]

- The background image is 1920×1080 (16:9) when the SYSTEM context cannot discover a monitor. This is intentional: Microsoft recommends 16:9 images and keeping important text within the central 4:3-safe region for mixed monitor aspect ratios. See [Configure Desktop and Lock Screen Backgrounds](https://learn.microsoft.com/en-us/windows/configuration/background/).
- Windows Education and Enterprise support a device lock-screen image through the Personalization CSP. The app applies an equivalent local policy, which is appropriate for a generated per-device local file. See [Personalization CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/personalization-csp).
- Uninstall restores the previous `LockScreenImage` only when the app still owns that setting. If another Intune profile or administrator changed it, uninstall exits `1` rather than overwrite the newer configuration.
- The computer name is not sensitive on a public library workstation, but treat it as inventory information. Do not add IP addresses, logged-on usernames, support tokens, or other sensitive data to the sign-in screen.
- PowerBGInfo is MIT licensed. Its included `License` file and pinned module version should remain with the package; test a module upgrade in the pilot group before changing the version.
