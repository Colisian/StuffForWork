# Microfilm Portrait Display — Intune Win32 App

Sets the matching Windows monitor-configuration `Rotation` values to `2`
(90 degrees clockwise / portrait), preserves the original values, and restores
them during uninstall.

> [!IMPORTANT]
> The install script defaults to `MonitorKeyPattern = '*'`. This is appropriate
> for dedicated, single-display microfilm workstations. If a device has another
> monitor that must remain landscape, identify the microfilm monitor's immediate
> child key below `GraphicsDrivers\Configuration`, replace `'*'` with a stable
> wildcard such as `'DEL40A8*'`, and test that customized script on a pilot.

## Files

| File | Purpose |
|---|---|
| `Install-MicrofilmPortraitDisplay.ps1` | Backs up and sets matching `Rotation` values to `2` |
| `Uninstall-MicrofilmPortraitDisplay.ps1` | Restores the exact original values |
| `Detect-MicrofilmPortraitDisplay.ps1` | Intune custom detection script |
| `Source\placeholder.txt` | Required source placeholder for `.intunewin` packaging |

## What the install changes

- Reads only the `Rotation` values under matching monitor keys at `00` and
  `00\00`.
- Exports the entire key below before editing:

  `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration`

- Sets only the matching `Rotation` values to `2`.
- Does **not** modify `Position.cx`, `Position.cy`, resolution, or placement.
- Saves original values and writes a state-based sentinel.
- Returns `3010` so Intune can report a soft reboot; it never forces a restart.

Runtime data is stored here:

`C:\ProgramData\UMD Libraries\MicrofilmPortraitDisplay`

Full `.reg` backups and restored-state archives are retained under `Backups`.
Install and uninstall logs are retained under `Logs`.

## Pilot: identify the monitor key

On one representative workstation, run this from an elevated 64-bit PowerShell
window:

```powershell
$root = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration'
Get-ChildItem -LiteralPath $root | ForEach-Object {
    foreach ($leaf in '00', '00\00') {
        $path = Join-Path -Path $_.PSPath -ChildPath $leaf
        $rotation = (Get-ItemProperty -LiteralPath $path -Name Rotation -ErrorAction SilentlyContinue).Rotation
        if ($null -ne $rotation) {
            [pscustomobject]@{
                MonitorKey = $_.PSChildName
                Leaf       = $leaf
                Rotation   = $rotation
            }
        }
    }
} | Format-Table -AutoSize
```

If there is more than one physical monitor, rotate the intended one once in
Windows Settings and rerun the inventory to correlate the changing key. Do not
assume keys beginning with `SIMULATED` or `NOEDID` identify the desired device.

## Build the placeholder `.intunewin`

The native PowerShell installer still starts with an `.intunewin` upload. From
this project directory, use the current Microsoft Win32 Content Prep Tool:

```powershell
IntuneWinAppUtil.exe -c .\Source -s placeholder.txt -o .\Output -q
```

Upload `Output\placeholder.intunewin` as the app package. The actual install and
uninstall logic is uploaded separately on the **Program** page.

## Intune configuration

### App information

| Setting | Recommended value |
|---|---|
| Name | `UMD Libraries - Microfilm Portrait Display` |
| Description | `Sets dedicated microfilm workstation displays to portrait orientation.` |
| Publisher | `University of Maryland Libraries` |
| Version | `1.0.0` |

### Program

| Setting | Value |
|---|---|
| Installer type | `PowerShell script` |
| Install script | Upload `Install-MicrofilmPortraitDisplay.ps1` |
| Uninstall script | Upload `Uninstall-MicrofilmPortraitDisplay.ps1` |
| Install behavior | `System` |
| Device restart behavior | `Determine behavior based on return codes` |

Keep the standard return-code mapping and confirm:

| Code | Type |
|---:|---|
| `0` | Success |
| `1` | Failed |
| `3010` | Soft reboot |

If your tenant exposes script properties, configure both installer scripts as:

| Setting | Value |
|---|---|
| Run as 32-bit | `No` |
| Enforce signature check | `No`, unless the scripts are signed with a trusted code-signing certificate |

### Requirements

| Setting | Value |
|---|---|
| Operating system architecture | `64-bit` |
| Minimum operating system | Your supported Windows 10/11 baseline |

### Detection rules

Choose **Use a custom detection script** and upload
`Detect-MicrofilmPortraitDisplay.ps1`.

| Setting | Value |
|---|---|
| Run script as 32-bit process on 64-bit clients | `No` |
| Enforce script signature check | `No`, unless signed |

Detection requires the sentinel, saved original-state file, and every target
`Rotation` value to equal `2`. A file/folder rule is intentionally not used.

### Assignment

Assign as **Required** to a small pilot device group first. After the install is
reported as successful, restart the workstation and visually confirm the
microfilm application, sign-in screen, pointer direction, and any attached
secondary display before expanding the assignment.

## Local verification

Use 64-bit Windows PowerShell as an administrator.

Dry-run the selection without changing registry state:

```powershell
.\Install-MicrofilmPortraitDisplay.ps1 -WhatIf
```

After a real install and restart:

```powershell
& .\Detect-MicrofilmPortraitDisplay.ps1
$LASTEXITCODE
```

Expected: one `Detected:` line and exit code `0`.

Inspect the sentinel:

```powershell
Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\UMD Libraries\MicrofilmPortraitDisplay'
```

Dry-run uninstall:

```powershell
.\Uninstall-MicrofilmPortraitDisplay.ps1 -WhatIf
```

## Recovery and troubleshooting

- Logs: `C:\ProgramData\UMD Libraries\MicrofilmPortraitDisplay\Logs`
- Full registry backups: `C:\ProgramData\UMD Libraries\MicrofilmPortraitDisplay\Backups`
- Intune Management Extension log:
  `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log`
- If the registry shows `2` but the display has not changed, restart Windows.
- If the display is portrait but upside down, that physical mount needs the
  inverse portrait value (`4`) rather than this package's value (`2`). Create a
  separate app/version for that hardware group; do not mix both orientations in
  one detection state.

## Security and operational notes

- The scripts contain no credentials and run non-interactively as SYSTEM.
- All registry access uses the 64-bit view, including when the host process is
  accidentally 32-bit.
- CrowdStrike or Rapid7 may record `reg.exe export` and writes below
  `GraphicsDrivers` as administrative configuration activity. The behavior is
  expected, narrowly scoped, and logged; pilot before broad deployment.
- Do not manually import the full `.reg` backup as a normal uninstall step. It
  can overwrite unrelated graphics changes made after installation. The
  uninstall script restores only the original `Rotation` values.

## References

- [Add, assign, and monitor a Win32 app in Microsoft Intune](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)
- [DISPLAYCONFIG_ROTATION enumeration](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ne-wingdi-displayconfig_rotation)
