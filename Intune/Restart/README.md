# RESTART Desktop Shortcut — Intune Win32 App

Deploys a **RESTART** shortcut to the Public Desktop (`C:\Users\Public\Desktop`) so it appears for every user. Same pattern as the [LOG OFF package](../LogOff/README.md) — system-context Win32 app, Public Desktop shortcut, custom detection script.

The shortcut targets `shutdown.exe /r /t 0` (there is no `restart.exe`).

## Contents

| File | Purpose |
| --- | --- |
| `Install-RestartShortcut.ps1` | Creates `RESTART.lnk` on the Public Desktop targeting `shutdown.exe /r /t 0` |
| `Uninstall-RestartShortcut.ps1` | Removes the Public Desktop shortcut |
| `Detection\Restart-Detection.ps1` | Custom detection: shortcut present **and** target/arguments match |

## Force or not?

The install script defaults to `/r /t 0` — **no `/f`**. Windows still prompts the user about apps with unsaved work, which is the right behavior on staff and public workstations.

For kiosk/lab machines where nothing user-owned should be running, pass `/r /t 0 /f` instead:

```powershell
.\Install-RestartShortcut.ps1 -Arguments '/r /t 0 /f'
```

If you change the arguments, update `$expectedArgs` in `Detection\Restart-Detection.ps1` to match — otherwise the app reports "not detected" forever and reinstalls on every check-in. (That coupling is deliberate: it's also what makes an argument change actually redeploy.)

> **Standard users**: `SeShutdownPrivilege` is granted to the local `Users` group on workstations by default, so a non-admin can use this shortcut. If a hardened baseline (CIS/STIG) has stripped `Shut down the system` from Users, the shortcut will fail with "Access is denied" for non-admins — check `secedit /export` or the effective User Rights Assignment before blaming the package.

## Package

A `.intunewin` is still required even with the PowerShell script installer — the app must have downloadable content, even though the install script here doesn't reference it.

```powershell
IntuneWinAppUtil.exe -c "<path>\Intune\Restart" -s Install-RestartShortcut.ps1 -o "<output-folder>"
```

## Intune App Configuration — PowerShell script installer (preferred)

On the **Program** page, set **Installer type** to **PowerShell script** instead of using command lines.

> UI quirk: on a new app the Installer type dropdown is greyed out until you type any character into the Install command field — do that first, then switch the dropdown.

| Setting | Value |
| --- | --- |
| Installer type | **PowerShell script** |
| Install script | Upload/paste `Install-RestartShortcut.ps1` |
| Uninstall script | Upload/paste `Uninstall-RestartShortcut.ps1` |
| Run as 32-bit | No |
| **Install behavior** | **System** |
| Device restart behavior | No specific action |
| Detection rules | Use a custom detection script → upload `Detection\Restart-Detection.ps1`; Run as 32-bit: **No** |
| Return codes | 0 = Success, 1 = Failure (defaults are fine) |

**Keep this repo the source of truth**: if a script is hot-fixed in the Intune portal, sync the change back to `Intune\Restart\` here.

### Alternative: command-line installer

| Setting | Value |
| --- | --- |
| Install command | `%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File Install-RestartShortcut.ps1` |
| Uninstall command | `%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File Uninstall-RestartShortcut.ps1` |

## Verify

On a target machine after sync:

```powershell
# Shortcut exists and points at shutdown.exe with the expected switches
$lnk = "$([Environment]::GetFolderPath('CommonDesktopDirectory'))\RESTART.lnk"
Test-Path $lnk
$s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$s.TargetPath; $s.Arguments; $s.IconLocation

# Install log
Get-Content 'C:\ProgramData\RestartShortcut\Install-RestartShortcut.log' -Tail 20

# Detection result as Intune sees it (run as SYSTEM via psexec if available)
powershell -File .\Detection\Restart-Detection.ps1; $LASTEXITCODE
```

Test the shortcut itself on a scratch VM, not your own workstation — `/t 0` means it restarts immediately with no countdown. `shutdown /a` only aborts a *pending* timed shutdown, so it will not save you here.

## Deploying alongside LOG OFF

These are separate Win32 apps with separate detection scripts and separate `C:\ProgramData` log folders, so they can be assigned to the same device groups without interfering. Nothing in this package touches the LOG OFF shortcut.
