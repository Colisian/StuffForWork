# Dell BIOS configuration for Intune

This package configures supported Dell devices through the already-installed Dell Command | Configure CLI (`cctk.exe`). Its configuration version is **1.0.0**.

## Settings enforced

| BIOS setting | Required value |
| --- | --- |
| Wake on LAN | `LanOnly` |
| AC Power Recovery | `Last` |
| Auto On | `Everyday` |
| Auto On hour | `6` |
| Auto On minute | `0` |

The script reads each setting, changes only noncompliant values, then reads all five settings again before marking the deployment successful.

## Important password and security behavior

This initial-deployment version does not create, clear, or supply a BIOS setup/admin password. It is suitable only for new Dell devices that do not already have a BIOS setup password.

If a device already has a BIOS password, Dell Command | Configure rejects any protected setting change without the current password. The installation fails, no compliance marker is written, and the existing password is not changed.

### Later enabling the BIOS password

If you later restore the password-enabled version of `Install-DellBIOSConfig.ps1`, it can set the password even when these five settings were already applied by this initial-deployment version. The installer establishes the password first, then skips settings that already match their required values.

Intune will not automatically rerun the app solely because the installer has changed: the current detection script will see `Version=1.0.0`, `State=Compliant`, and compliant BIOS values. To deploy the password-enabled revision, change `$ConfigVersion` in **both** `Install-DellBIOSConfig.ps1` and `Detect-DellBIOSConfig.ps1` (for example, from `1.0.0` to `1.0.1`), then repackage and reupload the Win32 app and its detection script. The old marker then fails detection and causes Intune to run the updated installer.

## Prerequisite and dependency

Deploy **Dell Command | Configure 5.2.2.292** first, as a separate Intune Win32 app, and add it as a dependency of this app. The install script searches the normal 64-bit CLI location:

```text
C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe
```

It also checks a few compatible alternate Program Files paths. The installation fails if `cctk.exe` is absent.

Dell's current documentation lists the supported option names and values used here: `--WakeonLAN=LanOnly`, `--AcPwrRcvry=Last`, `--AutoOn=Everyday`, `--AutoOnHr=6`, and `--AutoOnMn=0`. Auto On hour/minute are configured only after Auto On is enabled.

## Create the .intunewin package

1. Place the three `.ps1` files in the same source folder (this folder).
2. Use the Microsoft Win32 Content Prep Tool to create the `.intunewin` file. The setup file can be `Install-DellBIOSConfig.ps1`.
3. Upload the resulting package as a Windows app (Win32) in Intune.

## Exact Intune Win32 app settings

### Program

Use:

```text
Install command:
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DellBIOSConfig.ps1

Uninstall command:
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-DellBIOSConfig.ps1

Install behavior:
System

Device restart behavior:
Determine behavior based on return codes
```

Use **64-bit PowerShell**: in Intune, set **Run script as 32-bit process on 64-bit clients** to **No** wherever that option is presented. This keeps the deployment and detection registry view consistent.

### Detection rules

Choose **Use a custom detection script** and upload `Detect-DellBIOSConfig.ps1`.

The script exits `0` and writes a detection string only when all of these are true:

- The device is Dell hardware.
- `HKLM\SOFTWARE\StuffForWork\DellBIOSConfig` has `Version=1.0.0` and `State=Compliant`.
- `cctk.exe` remains installed.
- All five BIOS settings match the required values.

For detection, select **Run script as 32-bit process on 64-bit clients: No**.

## Verify a test deployment

After Intune reports the app installed, run the following from an elevated **64-bit** PowerShell session on the test Dell device. It queries the live BIOS values through Dell Command | Configure; each result should match the required value listed above.

```powershell
$cctk = Join-Path ${env:ProgramFiles(x86)} 'Dell\Command Configure\X86_64\cctk.exe'

& $cctk --WakeonLAN
& $cctk --AcPwrRcvry
& $cctk --AutoOn
& $cctk --AutoOnHr
& $cctk --AutoOnMn
```

Expected values are `WakeOnLan=LanOnly`, `AcPwrRcvry=Last`, `AutoOn=Everyday`, `AutoOnHr=6`, and `AutoOnMn=0`. You can also confirm that the installer completed its verification and wrote the Intune marker:

```powershell
Get-ItemProperty -Path 'HKLM:\SOFTWARE\StuffForWork\DellBIOSConfig' |
    Select-Object Version, State, PasswordState, AppliedUtc, CctkVersion, SettingsJson
```

For this password-free initial version, `State` should be `Compliant` and `PasswordState` should be `NotConfigured`. Review the newest log in `C:\ProgramData\Dell\BIOSConfig` if either check does not show the expected result.

### Dependencies and assignments

- Add the Dell Command | Configure Win32 app as a dependency and ensure it installs first.
- Use **System** install behavior. BIOS configuration must not run in a standard user context.
- Assign initially to a small Dell-device pilot group. The script returns success without changes on non-Dell hardware, but target Dell devices deliberately.

## Logs and marker

Deployment and detection logs are kept under:

```text
C:\ProgramData\Dell\BIOSConfig
```

Successful deployments create this 64-bit registry marker:

```text
HKLM\SOFTWARE\StuffForWork\DellBIOSConfig
```

The marker stores version, UTC apply time, cctk path/version, password state (`NotConfigured`), and the non-secret settings JSON.

## Uninstall / rollback behavior

The default uninstall command removes **only** the deployment marker. It does not alter a BIOS password and does not reverse the BIOS values, because this package does not know the prior safe values.

To explicitly clear the current setup password, use a separate, tightly controlled Intune app with this command (replace the placeholder):

```text
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-DellBIOSConfig.ps1 -ClearBiosPassword -BiosPassword "REPLACE_WITH_CURRENT_BIOS_PASSWORD"
```

This is intentionally not the default uninstall command. It invokes Dell's documented `--SetupPwd= --ValSetupPwd=<old-password>` pattern, and retains the marker if the password-clear operation fails.

## Dell references

- [Dell Command | Configure 5.x Command-line Interface Reference Guide](https://www.dell.com/support/manuals/en-us/command-configure/dcc_5.x_ref_guide)
- [Dell Command: Configure error codes](https://www.dell.com/support/kbdoc/en-us/000147084/dell-command-configure-error-codes)
