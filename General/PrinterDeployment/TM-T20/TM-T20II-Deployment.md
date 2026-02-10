# Epson TM-T20II Receipt Printer - Intune Deployment

## Overview

This package deploys the Epson TM-T20II receipt printer driver via Microsoft Intune as a Win32 app. The driver is staged into the Windows driver store so that when the printer is physically connected via USB, Windows automatically creates the printer and port through the Epson Dynamic Print Monitor.

## How It Works

### Install Flow (`install.cmd` → `Add_Printers.ps1`)

1. **Stage the INF driver** - Uses `pnputil.exe /a` to add the Epson INF file (`EA5INSTMT20II.INF`) and associated driver binaries into the Windows driver store
2. **Register the driver** - Calls `Add-PrinterDriver` to register `EPSON TM-T20II Receipt5` with the Windows print subsystem
3. **USB auto-detection handles the rest** - When the printer is plugged in via USB, the Epson Dynamic Print Monitor automatically:
   - Creates a `USB001` port bound to the physical device
   - Creates the `EPSON TM-T20II Receipt5` printer on that port

### Detection (`Detection.ps1`)

- Checks for the existence of the `EPSON TM-T20II Receipt5` printer via `Get-Printer`
- Returns exit code `0` if found (installed), exit code `1` if not (triggers reinstall)
- Logs results to `c:\windows\temp\printer_detection.log`

### Uninstall Flow (`uninstall.cmd` → `Remove_Printers.ps1`)

1. Removes the `EPSON TM-T20II Receipt5` printer object
2. Removes the registered printer driver from Windows
3. Looks up the published OEM INF name (e.g., `oem5.inf`) and removes it from the driver store via `pnputil.exe /delete-driver`

### File Inventory

| File | Purpose |
|------|---------|
| `install.cmd` | Entry point for Intune install - calls `Add_Printers.ps1` with bypass execution policy |
| `uninstall.cmd` | Entry point for Intune uninstall - calls `Remove_Printers.ps1` |
| `Add_Printers.ps1` | Stages INF and registers the printer driver |
| `Remove_Printers.ps1` | Removes printer, driver, and staged INF |
| `Detection.ps1` | Intune detection script |
| `printers.csv` | Reference file with printer name, driver, and location info |
| `EA5INSTMT20II.INF` | Epson driver INF file |
| `ea5instmt20ii.cat` | Driver catalog (signature) file |
| `EA5LMTMT20II.dat` | Driver data file |
| `EA5MDLTMT20II.GP_` | Compressed driver model file |
| `EA5PIITMT20II.IN_` | Compressed driver info file |
| `EA5RESTMT20II.DL_` | Compressed driver resource DLL |
| `amd64/` | 64-bit driver binaries (DLLs and installer) |

---

## Intune Deployment Guide

### Prerequisites

- Access to the [Microsoft Intune admin center](https://intune.microsoft.com)
- The [Microsoft Win32 Content Prep Tool](https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool) (`IntuneWinAppUtil.exe`)
- All TM-T20 deployment files in a single folder (scripts, driver files, and `amd64/` subfolder)

### Step 1: Create the `.intunewin` Package

1. Download `IntuneWinAppUtil.exe` if you don't already have it
2. Open a command prompt and run:

   ```cmd
   IntuneWinAppUtil.exe -c "C:\path\to\TM-T20" -s install.cmd -o "C:\path\to\output"
   ```

   - `-c` = source folder containing all deployment files
   - `-s` = setup file (entry point) — use `install.cmd`
   - `-o` = output folder for the generated `.intunewin` file

3. This produces `install.intunewin` in your output folder

### Step 2: Create the Win32 App in Intune

1. Navigate to **Microsoft Intune admin center** → **Apps** → **Windows** → **Add**
2. Select **Windows app (Win32)** and click **Select**
3. Upload `install.intunewin` as the app package file

### Step 3: App Information

| Field | Value |
|-------|-------|
| Name | `Epson TM-T20II Receipt Printer Driver` |
| Description | `Stages the Epson TM-T20II driver for USB auto-detection` |
| Publisher | `Epson` |
| Category | `Computer Management` (or your preference) |

### Step 4: Program Settings

| Field | Value |
|-------|-------|
| Install command | `install.cmd` |
| Uninstall command | `uninstall.cmd` |
| Install behavior | **System** (must run as SYSTEM to stage drivers) |
| Device restart behavior | `No specific action` |
| Return codes | Leave defaults (0 = Success, 1707 = Success, 3010 = Soft reboot, 1618 = Retry) |

### Step 5: Requirements

| Field | Value |
|-------|-------|
| Operating system architecture | **64-bit** |
| Minimum operating system | `Windows 10 1903` (or your minimum supported version) |

### Step 6: Detection Rules

1. Select **Use a custom detection script**
2. Upload `Detection.ps1`
3. Set the following:

| Field | Value |
|-------|-------|
| Script file | `Detection.ps1` |
| Run script as 32-bit process on 64-bit clients | **No** |
| Enforce script signature check | **No** |

The detection script returns exit code `0` when `EPSON TM-T20II Receipt5` is found, and exit code `1` when it is not.

### Step 7: Assignments

1. Under **Required**, add the device group(s) containing workstations that have the TM-T20II connected
2. Alternatively, use **Available for enrolled devices** if you want users to install on-demand from Company Portal

### Step 8: Review and Create

1. Review all settings and click **Create**
2. Intune will distribute the package to assigned devices on next sync

### Post-Deployment Notes

- The driver is staged silently in the background. The printer **will not appear** until the TM-T20II is physically connected via USB.
- If the printer is already plugged in during install, it should appear within a few seconds of the script completing.
- If the printer does not appear after connecting USB, restart the Print Spooler service: `Restart-Service Spooler -Force`
- Check `c:\windows\temp\printer_install.log` on the endpoint for install troubleshooting.

### Redeployment / Updates

To push an updated version:

1. Repackage with `IntuneWinAppUtil.exe` using the updated files
2. In Intune, edit the existing app and upload the new `.intunewin` file
3. Increment the version number so Intune recognizes the update
4. Devices will pick up the new package on next sync

---

## Logs

All scripts write transcript logs to `c:\windows\temp\`:

- `printer_install.log` - Install output
- `printer_detection.log` - Detection output
- `printer_remove.log` - Removal output

---

## Issue Resolved (v1.0 → v2.0)

### Symptom

After a fresh Windows wipe and Intune re-deployment, the printer appeared installed with no errors, but test pages would not print. The print job did not appear in the queue — it vanished as if it printed successfully, but nothing came out of the printer.

### Root Cause: Duplicate USB Port Conflict

The v1.0 scripts manually created a **Local Monitor** port named `USB001` using `Add-PrinterPort` and then created printer objects on that port. However, when the Epson driver is staged via `pnputil` and the printer is physically connected, the driver automatically creates its own `USB001` port via the **Dynamic Print Monitor**.

This resulted in **two ports both named `USB001`**:

| Port Name | Port Monitor | Created By | Talks to Hardware? |
|-----------|-------------|------------|-------------------|
| `USB001` | Dynamic Print Monitor | Epson driver (automatic) | Yes |
| `USB001` | Local Monitor | `Add_Printers.ps1` script | No |

The script-created printers were bound to the **Local Monitor** port, which has no connection to the physical USB device. Print jobs sent to this port were silently discarded.

### Why It Worked Before

On the original deployment, the timing or driver state may have resulted in only one `USB001` port existing, so the printer objects happened to bind to the correct one. After a clean wipe, the Epson driver created its port first, and the script's attempt to create a second one caused the conflict.

### Additional v1.0 Issues Fixed

- **Two CSV entries creating duplicate printers** - The CSV defined both `EPSON TM-T20II` and `EPSON TM-T20II Receipt5`, but only one physical printer exists on one USB port
- **Port removal failing in install loop** - The script tried to remove `USB001` while printers were still attached, causing cascading errors
- **`pnputil /d` using local path** - The uninstall script passed the local INF file path to `pnputil /d`, but this flag requires the published OEM name (e.g., `oem5.inf`), so driver removal silently failed
- **Detection checking for two printers** - The detection script required both printer names to exist, but only one is created by the Dynamic Print Monitor

### Resolution

Removed all manual port and printer creation from the install script. The Epson Dynamic Print Monitor correctly handles USB port and printer creation automatically when:

1. The driver is staged in the driver store
2. The printer is physically connected via USB

The scripts now only manage the **driver** lifecycle (stage/remove), and let the Epson driver subsystem manage the **printer and port** lifecycle.
