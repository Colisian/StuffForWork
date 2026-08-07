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

1. In `Install-DellBIOSConfig.ps1`, replace `REPLACE_WITH_YOUR_STANDARD_BIOS_PASSWORD` with the approved standard BIOS setup/admin password before packaging. Alternatively, pass `-BiosPassword` in the install command, but that places the secret in Intune command-line metadata.
2. The script uses Dell's documented `--SetupPwd` behavior to determine state. An exit code of **0** means there was no setup password and the script set the standard password. Exit code **41** means a setup password already exists; it is not changed.
3. If an existing device has a different unknown password and a setting needs to change, cctk will reject the supplied password and the installation fails safely. No marker is written.
4. An `.intunewin` package and PowerShell script are **not secret stores**. A sufficiently privileged user can recover an embedded password. Do not store this package, the password, or logs in broadly accessible locations. Do not commit a real password to source control.
5. The script never writes the password to its own log. The password is necessarily presented to cctk at runtime.

## Prerequisite and dependency

Deploy **Dell Command | Configure 5.2.2.292** first, as a separate Intune Win32 app, and add it as a dependency of this app. The install script searches the normal 64-bit CLI location:

```text
C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe
```

It also checks a few compatible alternate Program Files paths. The installation fails if `cctk.exe` is absent.

Dell's current documentation lists the supported option names and values used here: `--WakeonLAN=LanOnly`, `--AcPwrRcvry=Last`, `--AutoOn=Everyday`, `--AutoOnHr=6`, and `--AutoOnMn=0`. Auto On hour/minute are configured only after Auto On is enabled.

## Create the .intunewin package

1. Make the password change described above.
2. Place the three `.ps1` files in the same source folder (this folder).
3. Use the Microsoft Win32 Content Prep Tool to create the `.intunewin` file. The setup file can be `Install-DellBIOSConfig.ps1`.
4. Upload the resulting package as a Windows app (Win32) in Intune.

## Exact Intune Win32 app settings

### Program

After replacing the placeholder in the install script, use:

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

The marker stores version, UTC apply time, cctk path/version, password state (`SetByDeployment` or `AlreadyExisted`), and the non-secret settings JSON. It never stores the BIOS password.

## Uninstall / rollback behavior

The default uninstall command removes **only** the deployment marker. It intentionally does not clear the BIOS password and does not reverse the BIOS values, because this package does not know the prior safe values.

To explicitly clear the current setup password, use a separate, tightly controlled Intune app with this command (replace the placeholder):

```text
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-DellBIOSConfig.ps1 -ClearBiosPassword -BiosPassword "REPLACE_WITH_CURRENT_BIOS_PASSWORD"
```

This is intentionally not the default uninstall command. It invokes Dell's documented `--SetupPwd= --ValSetupPwd=<old-password>` pattern, and retains the marker if the password-clear operation fails.

## Dell references

- [Dell Command | Configure 5.x Command-line Interface Reference Guide](https://www.dell.com/support/manuals/en-us/command-configure/dcc_5.x_ref_guide)
- [Dell Command: Configure error codes](https://www.dell.com/support/kbdoc/en-us/000147084/dell-command-configure-error-codes)
