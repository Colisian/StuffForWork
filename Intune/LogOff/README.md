# LOG OFF Desktop Shortcut — Intune Win32 App

Deploys a **LOG OFF** shortcut to the Public Desktop (`C:\Users\Public\Desktop`) so it appears for every user. Replaces the old per-user deployment, whose shortcut landed on individual user desktops and was invisible to the SYSTEM-context detection script.

## Contents

| File | Purpose |
|---|---|
| `Install-LogOffShortcut.ps1` | Creates `LOG OFF.lnk` on the Public Desktop targeting `logoff.exe`; removes stale per-user copies (including OneDrive-redirected desktops) |
| `Uninstall-LogOffShortcut.ps1` | Removes the Public Desktop shortcut |
| `Detection\LogOff-Detection.ps1` | Custom detection: shortcut present on Public Desktop |

## Package

```powershell
IntuneWinAppUtil.exe -c "<path>\Intune\LogOff" -s Install-LogOffShortcut.ps1 -o "<output-folder>"
```

> The `Detection` folder gets bundled into the `.intunewin` too — harmless, but you can point `-c` at a copy containing only the two scripts if you want a clean package.

## Intune App Configuration

| Setting | Value |
|---|---|
| Install command | `%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File Install-LogOffShortcut.ps1` |
| Uninstall command | `%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File Uninstall-LogOffShortcut.ps1` |
| **Install behavior** | **System** (this is the fix — the old app was User) |
| Device restart behavior | No specific action |
| Detection rules | Use a custom detection script → upload `Detection\LogOff-Detection.ps1`; Run as 32-bit: **No** |
| Return codes | 0 = Success, 1 = Failure (defaults are fine) |

## Cutover from the old per-user app

1. **Unassign (or delete) the old per-user Win32 app first.** If it stays assigned, it will keep re-creating per-user shortcuts that the install script then deletes — a tug-of-war.
2. Assign this app as **Required** to the same device groups.
3. The install script cleans up leftover per-user shortcuts on its own, so no separate cleanup script is needed.

## Verify

On a target machine after sync:

```powershell
# Shortcut exists and points at logoff.exe
$lnk = "$([Environment]::GetFolderPath('CommonDesktopDirectory'))\LOG OFF.lnk"
Test-Path $lnk
(New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath

# Install log
Get-Content 'C:\ProgramData\LogOffShortcut\Install-LogOffShortcut.log' -Tail 20

# Detection result as Intune sees it (run as SYSTEM via psexec if available)
powershell -File .\Detection\LogOff-Detection.ps1; $LASTEXITCODE
```
