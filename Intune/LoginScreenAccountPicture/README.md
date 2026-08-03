# UMD Libraries Login-Screen Account Picture

## Outcome

This Win32 app replaces the Windows **default account picture** with the UMD
Libraries artwork and enables **Apply the default account picture to all
users**. It changes the circular user tile on the Windows sign-in screen; it
does not replace the lock-screen or sign-in-screen background.

The policy applies one picture to local, AD, and Microsoft Entra users on the
device and prevents users from selecting personal account pictures while the
policy is enabled. Assign this app to public-computer **device groups**, not
user groups.

Microsoft documents the policy as
`./Device/Vendor/MSFT/Policy/Config/ADMX_Cpls/UseDefaultTile` and maps it to:

- Registry key: `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer`
- Value: `UseDefaultTile` (`DWORD 1`)
- Friendly name: `Apply the default account picture to all users`

Reference: [ADMX_Cpls Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-cpls#usedefaulttile)

## Package layout

```text
LoginScreenAccountPicture/
├── Intune/
│   └── Detect-LoginScreenAccountPicture.ps1
├── Source/
│   ├── Install-LoginScreenAccountPicture.cmd
│   ├── Install-LoginScreenAccountPicture.ps1
│   ├── Package.placeholder
│   ├── UMD-AccountPicture-192.png
│   ├── UMD-AccountPicture-448.png
│   ├── Uninstall-LoginScreenAccountPicture.cmd
│   └── Uninstall-LoginScreenAccountPicture.ps1
└── README.md
```

The supplied source images are already the correct 448x448 and 192x192
dimensions. Install creates the remaining 48x48, 40x40, and 32x32 PNG files,
plus the compatibility JPG and BMP files, on the endpoint.

## Safety and rollback behavior

Install backs up every existing `user*` default image and the prior
`UseDefaultTile` state under:

```text
C:\ProgramData\UMDLibraries\LoginScreenAccountPicture\State
```

Uninstall restores that baseline. Before restoring, it verifies that each
current image still has the hash deployed by this app. If another product or
administrator changed a managed image afterward, uninstall returns `1` and
leaves the conflicting file and rollback data untouched.

Logs are retained here:

```text
C:\ProgramData\UMDLibraries\LoginScreenAccountPicture\Install-LoginScreenAccountPicture.log
C:\ProgramData\UMDLibraries\LoginScreenAccountPicture\Uninstall-LoginScreenAccountPicture.log
```

## 1. Build the `.intunewin`

Use the latest Microsoft Win32 Content Prep Tool. From this repository root:

```powershell
$packageRoot = Join-Path (Get-Location) 'LoginScreenAccountPicture'
$outputRoot = Join-Path $packageRoot 'Output'
New-Item -Path $outputRoot -ItemType Directory -Force | Out-Null

& 'C:\Tools\IntuneWinAppUtil.exe' `
    -c (Join-Path $packageRoot 'Source') `
    -s 'Package.placeholder' `
    -o $outputRoot `
    -q
```

Change only the tool path if `IntuneWinAppUtil.exe` is stored elsewhere. The
`-s` value is intentionally a required placeholder: the PowerShell installer
performs the installation, while all companion files stay in the package.

Expected output:

```text
LoginScreenAccountPicture\Output\Package.intunewin
```

The output name can vary with the Content Prep Tool version because the setup
placeholder is used only to satisfy packaging metadata.

## 2. Create the Intune Win32 app

In the Intune admin center:

1. Go to **Apps > All apps > Create**.
2. Select **Windows app (Win32)**.
3. Upload the `.intunewin` file.
4. Use these app details:

| Setting | Value |
|---|---|
| Name | `UMD Libraries - Login Screen Account Picture` |
| Description | `Standard UMD Libraries account tile for public Windows computers.` |
| Publisher | `University of Maryland Libraries` |
| App version | `1.0.0` |
| Install behavior | `System` |
| Device restart behavior | `No specific action` |
| Allow available uninstall | `No` |

Microsoft's current Win32-app workflow documents a native **PowerShell
script** installer. Select that installer type and upload:

```text
Source\Install-LoginScreenAccountPicture.ps1
```

Set **Run script as 32-bit process on 64-bit clients** to **No**. If the tenant
uses a trusted code-signing certificate, sign the scripts and set **Enforce
script signature check** to **Yes**. Otherwise use **No** during the pilot; do
not enable signature enforcement on unsigned files.

Microsoft currently documents the removal field as an **Uninstall command**,
not a second uploaded PowerShell script. Use this package-local wrapper:

```text
Uninstall-LoginScreenAccountPicture.cmd
```

The CMD wrapper selects 64-bit Windows PowerShell at runtime and avoids relying
on Intune to expand `%SystemRoot%` in the uninstall field. If your tenant UI
offers a native **Uninstall PowerShell script** upload, upload this instead:

```text
Source\Uninstall-LoginScreenAccountPicture.ps1
```

Microsoft reference: [Add, assign, and monitor a Win32 app](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)

## 3. Requirements and detection

Recommended requirements:

| Setting | Value |
|---|---|
| Operating system architecture | `64-bit` (include ARM64 only after a pilot) |
| Minimum operating system | Match the public-computer Windows 10/11 baseline |

For **Detection rules**:

1. Select **Use a custom detection script**.
2. Upload `Intune\Detect-LoginScreenAccountPicture.ps1`.
3. Set **Run script as 32-bit process on 64-bit clients** to **No**.
4. Set signature enforcement consistently with the installer.

Detection checks the registry completion sentinel, package version, enforced
policy, existence of all seven generated images, and every installed SHA-256
hash. It emits one short stdout line only when compliant.

## 4. Assign and pilot

1. Assign as **Required** to a small public-computer pilot device group.
2. Install while nobody is using the pilot machine if practical.
3. Sign out or restart; Windows may cache the current tile until the next
   sign-in-screen session.
4. Confirm the correct tile for at least one library/public account and the
   local administrator tile.
5. Expand to the production public-computer device group.

Do not also configure `UseDefaultTile` through a Settings Catalog profile while
this Win32 app owns it. One management source avoids rollback conflicts and
unclear reporting. If you later move policy ownership to Settings Catalog,
supersede this app with an image-only version rather than assigning both.

For an uninstall assignment, remove the device group from **Required** before
assigning it to **Uninstall**. A group targeted by both intents remains
installed.

## Verification commands

Run these in 64-bit elevated Windows PowerShell on a pilot endpoint:

```powershell
Get-ItemProperty `
    -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
    -Name UseDefaultTile

Get-ItemProperty `
    -LiteralPath 'HKLM:\SOFTWARE\UMDLibraries\Intune\LoginScreenAccountPicture'

Get-ChildItem `
    -LiteralPath "$env:ProgramData\Microsoft\User Account Pictures" `
    -Filter 'user*' |
    Select-Object Name, Length, LastWriteTime

& '.\LoginScreenAccountPicture\Intune\Detect-LoginScreenAccountPicture.ps1'
$LASTEXITCODE
```

Expected detection output:

```text
UMD Libraries account picture 1.0.0 detected
0
```

To inspect IME and package logs:

```powershell
Get-Content `
    -LiteralPath 'C:\ProgramData\UMDLibraries\LoginScreenAccountPicture\Install-LoginScreenAccountPicture.log' `
    -Tail 100

Get-Content `
    -LiteralPath 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log' `
    -Tail 100
```

## Optional command-line installer method

The same package also supports the traditional Win32 command-line method with
no file edits:

```text
Install command:   Install-LoginScreenAccountPicture.cmd
Uninstall command: Uninstall-LoginScreenAccountPicture.cmd
```

The native PowerShell installer is preferred for this deployment because its
return code is reported directly and the install logic remains visible in the
Intune app configuration.

## Updating the artwork or version

1. Keep the source dimensions at exactly 448x448 and 192x192.
2. Replace the two PNG files in `Source`.
3. Calculate their SHA-256 hashes:

   ```powershell
   Get-FileHash -Algorithm SHA256 `
       '.\LoginScreenAccountPicture\Source\UMD-AccountPicture-448.png', `
       '.\LoginScreenAccountPicture\Source\UMD-AccountPicture-192.png'
   ```

4. Update both expected source hashes and `Version` in the install script.
5. Update `ExpectedVersion` in the detection script.
6. Repackage, pilot, and deploy with Win32 supersedence. For an in-place artwork
   update, do not uninstall the previous version; install retains the original
   Windows baseline for a future rollback.

## Security notes

- No credentials or user data are stored.
- All deployment writes occur as SYSTEM in Windows' shared account-picture
  directory, HKLM policy/sentinel keys, and the component log/state directory.
- The rollback directory contains only Windows' previous default image files
  and policy metadata.
- The scripts do not use encoded commands, user-session injection, downloads,
  or interactive UI.
- CrowdStrike or Rapid7 may record SYSTEM replacing files under
  `C:\ProgramData\Microsoft\User Account Pictures`. Pilot first and investigate
  any alert by script/package hash. Do not create a broad path or PowerShell
  exclusion.
