# Pharos Remote 9.2 — Intune Win32 Deployment Runbook

## Summary

This package silently installs Pharos Remote `9.2.10000.194`, configures it to connect to the Pharos Database Service at `LIBRDB407DV.ad.umd.edu:2355` with a 120-second timeout, and copies `Pharos Remote.lnk` from the all-users Start Menu to the Public Desktop.

The package uses the registry-seeding behavior described in the referenced 2012 Uniprint 8.2 article, corroborated by the registry state captured after the local manual installation. The local installer is Uniprint 9.2, so validate install, launch, database login, and uninstall on a pilot device before broad assignment.

## Review findings

| Item | Finding |
|---|---|
| Installer | `RemoteInstaller.exe` version `9.2.10000.194` |
| Installer SHA-256 | `DCC4D481CA0135DB23C27F3E78D4CE67B3052F0FE35621CF08AE3D5D0769A656` |
| Digital signature | Not signed |
| Database Service | `LIBRDB407DV.ad.umd.edu`, TCP 2355 |
| Required registry view | 32-bit: `HKLM\SOFTWARE\WOW6432Node\Pharos\Database Server` on 64-bit Windows |
| Required .NET | .NET Framework 4.6 or later |
| Install context | SYSTEM, non-interactive |

The original scripts differed: the workspace script wrote the explicit 32-bit path, while the installer-source script wrote `HKLM\SOFTWARE\Pharos\Database Server`. The latter targets the wrong view when run in a 64-bit PowerShell host. Both also omitted hash validation, prerequisite checks, exit-code handling, post-install validation, logging, and Intune detection state.

## Package files

- `RemoteInstaller.exe` — vendor installer and required `IntuneWinAppUtil -s` placeholder
- `InstallPharosRemote.ps1` — SYSTEM install wrapper
- `UninstallPharosRemote.ps1` — SYSTEM uninstall wrapper
- `DetectPharosRemote.ps1` — custom Intune detection script
- `PharosRemote-Intune-Runbook.md` — this runbook

Logs are written on the endpoint to:

- `C:\ProgramData\PharosRemote\InstallPharosRemote.log`
- `C:\ProgramData\PharosRemote\UninstallPharosRemote.log`

## Build the `.intunewin`

Method A is the recommended deployment because the versioned PowerShell wrapper remains inside the package.

```powershell
$contentPrepTool = 'C:\Users\cmcleod1\OneDrive - University of Maryland\Documents\Work\Intune\3-Microsoft-Win32-Content-Prep-Tool-master\IntuneWinAppUtil.exe'
$sourceFolder = 'C:\Users\cmcleod1\OneDrive - University of Maryland\Documents\Work\StuffForWork\Intune\PharosRemote'
$outputFolder = 'C:\Users\cmcleod1\OneDrive - University of Maryland\Documents\Work\StuffForWork\Intune\PharosRemoteOutput'

& $contentPrepTool -c $sourceFolder -s 'RemoteInstaller.exe' -o $outputFolder -q
```

The completed package is named `PharosRemote-9.2.10000.194.intunewin` in `PharosRemoteOutput`. Rebuilding an `.intunewin` creates new encryption material, so a later build will normally have a different package hash even when the source is unchanged.

## Intune Win32 app settings

### App information

| Setting | Value |
|---|---|
| Name | Pharos Remote 9.2.10000.194 |
| Publisher | Pharos Systems International |
| App version | 9.2.10000.194 |
| Category | Utilities or IT Administration |

### Program

Install command:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\InstallPharosRemote.ps1
```

Uninstall command:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\UninstallPharosRemote.ps1
```

| Setting | Value |
|---|---|
| Install behavior | System |
| Device restart behavior | Determine behavior based on return codes |
| Return codes | Keep Intune defaults for 0, 1641, and 3010 |
| Installation time required | 30 minutes |
| Allow available uninstall | Only after pilot uninstall validation |

### Requirements

- Architecture: 64-bit
- Minimum operating system: use the lowest supported Windows 10/11 build still permitted by the Libraries baseline
- Disk space: at least 150 MB recommended for install and working space
- Network: line of sight to `LIBRDB407DV.ad.umd.edu` on TCP 2355; campus network or VPN may be required
- Dependency: .NET Framework 4.6 or later (the install wrapper also enforces this)

### Detection rule

Choose **Use a custom detection script** and upload `DetectPharosRemote.ps1`.

- Run script as 32-bit process on 64-bit clients: **No**
- Enforce script signature check: **No**, unless the script is signed with the UMD code-signing certificate first

Detection requires all of the following:

1. UMD post-install sentinel for package version and installer hash.
2. Correct 32-bit Pharos Database Server values.
3. `AdminLauncher.exe` and `Uninst.exe` in the recorded Pharos `Bin` directory.
4. `C:\Users\Public\Desktop\Pharos Remote.lnk`.

This avoids a false positive if registry settings are written but the vendor installer fails.

## Pilot deployment and verification

1. Assign as **Available** to a small IT pilot device group.
2. Confirm the endpoint is on campus or VPN.
3. Install from Company Portal.
4. Review the install log.
5. Run the checks below from an elevated 64-bit PowerShell window.
6. Launch **Pharos Remote** from the Start menu and verify login and expected limited contexts.
7. Test uninstall on a device that does not have another Pharos Administrator or client component installed.

```powershell
Test-NetConnection -ComputerName 'LIBRDB407DV.ad.umd.edu' -Port 2355

Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Pharos\Database Server' |
    Select-Object 'Host Address', 'Port Name', Timeout

& .\DetectPharosRemote.ps1
$LASTEXITCODE

Get-Content -LiteralPath 'C:\ProgramData\PharosRemote\InstallPharosRemote.log' -Tail 100

Test-Path -LiteralPath 'C:\Users\Public\Desktop\Pharos Remote.lnk'
```

Expected detection exit code: `0`.

## Uninstall caution

Pharos documents `Uninst.exe` as the component uninstaller and documents `/s Popups` for silent Popup removal, but the current public Remote documentation does not state a silent Remote component token. `UninstallPharosRemote.ps1` uses the analogous `/s Remote` token. Treat this as a pilot-gated assumption before enabling Company Portal uninstall or Required uninstall assignments.

The wrapper intentionally leaves `HKLM\SOFTWARE\WOW6432Node\Pharos\Database Server` in place because that configuration may be shared with other Pharos components. It removes only the UMD Intune sentinel.

## Security and operations notes

- `RemoteInstaller.exe` is not Authenticode-signed. The wrapper pins its known SHA-256 and refuses to run a changed file. Obtain future installers directly from the Pharos Administrator `Packages > Client Installers` context, then update the version and expected hash in both install and detection scripts.
- Submit the hash to the security team before broad deployment if CrowdStrike blocks or quarantines the unsigned installer. Prefer a hash-specific exception after review; do not exclude the entire Pharos or Intune cache directories.
- Rapid7 may report new executables or the older .NET-based application after deployment. Record the approved version and hash in the change ticket so findings can be triaged without a broad vulnerability exception.
- The database host name is the server running the Pharos Database Service, not necessarily the SQL Server.
- From the packaging workstation on 2026-08-26, DNS resolved `LIBRDB407DV.ad.umd.edu` to `128.8.212.77`, but TCP 2355 did not connect during the review. Re-test from the intended campus/VPN pilot network before deployment.

## Rollback

If the silent uninstall pilot fails, do not assign uninstall broadly. Remove the Intune assignment, collect `C:\ProgramData\PharosRemote\UninstallPharosRemote.log`, and confirm the correct Remote component token with Pharos Support. Use the installed Pharos Uninstaller interactively only on a controlled pilot device while documenting the selected component and resulting command behavior.
