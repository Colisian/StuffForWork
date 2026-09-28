---
title: Epson TM-T20II Receipt Printer â€“ Intune APD5 Deployment
tags: [intune, win32, printer, epson, runbook]
version: 3.1.0
date: 2026-09-28
author: Oji
---

# Epson TM-T20II Receipt Printer â€“ Intune APD5 Deployment (v3)

## Why v3 (what was wrong with v2)

| Symptom | Cause | v3 fix |
|---|---|---|
| Company Portal says **Failed** even though the driver installed | `Detection.ps1` looked for the printer queue, which only exists while the printer is **plugged in**, so a machine without the printer connected always fails detection. | Detection checks install state: sentinel + driver + Epson port monitor. |
| Printer shows up but jobs silently vanish or don't print | v2 only staged the INF, so Windows put the queue on a generic `USB001` port. The working manual setup uses **`ESDPRT001` â€“ "USB TM-T20II"**, a port owned by Epson's **Port Communication Service (PCS)**, which v2 never installed. | Install the full **EPSON Advanced Printer Driver 5.13** silently (`/s`): driver + PCS port monitor + Epson PnP registration. |
| Leftover `USB001 â€“ Local Port` entry | Created by v1 `Add-PrinterPort` | The install script removes unused Local Monitor `USB###` ports and legacy queues. |

### What `APD_513_T20II.exe /s` installs
- Driver `EPSON TM-T20II Receipt5` (same INF as v2: `EA5INSTMT20II.INF`)
- `PCS64.msi`: **EPSON Port Handler Monitor** plus the Port Communication Service (provides `ESDPRT###` ports)
- `PrinterReg64.msi`: turns on Epson's "Enable PnP Install", so plugging in the USB printer creates the queue on `ESDPRT###`
- TM-T20II Utility (APD5 Utility)

## Files

| File | Where | Purpose |
|---|---|---|
| `Install-EpsonTMT20II.ps1` | repo + package | Cleans up legacy queues/ports, runs `/s`, verifies, re-enumerates a connected printer, writes the sentinel |
| `Uninstall-EpsonTMT20II.ps1` | repo + package | `/s /uninstall`, removes leftover queues/driver/driver-store entry and the sentinel |
| `Detect-EpsonTMT20II.ps1` | repo (upload to Intune) | Custom detection |
| `Build-IntunePackage.ps1` | repo | Extracts `APD_513_T20II.exe` from the Epson zip, checks its signature, builds the `.intunewin` |
| `APD_513_T20II.exe` | package only | Epson installer (signed, Seiko Epson Corp.). Not committed to git. |

Build output: `Work\Intune\2-IntuneApps\EpsonTMT20II-APD\Output\Install-EpsonTMT20II.intunewin`

## Build

```powershell
cd "â€¦\StuffForWork\General\RecepitPrinterDeployment\TM-T20II-APD"
.\Build-IntunePackage.ps1          # -WhatIf to preview
```

## Intune Win32 app settings

**App information**
- Name: `Epson TM-T20II Receipt Printer (APD 5.13)`
- Publisher: `Seiko Epson` Â· Version: `5.13.0.0`

**Program â€“ Method A (default, command line)**

| Field | Value |
|---|---|
| Install command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-EpsonTMT20II.ps1` |
| Uninstall command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-EpsonTMT20II.ps1` |
| Install behavior | **System** |
| Device restart behavior | No specific action |
| Return codes | Defaults (0 success, 1 = failure from script) |

> `sysnative` forces 64-bit PowerShell (the Intune Management Extension is 32-bit). The scripts also relaunch themselves in 64-bit if needed.

**Program â€“ Method B (PowerShell script upload)**

| Field | Value |
|---|---|
| Installer type | **PowerShell script** |
| Install script | upload `Install-EpsonTMT20II.ps1` |
| Uninstall script | upload `Uninstall-EpsonTMT20II.ps1` |
| Install behavior | **System** |
| Return codes | Defaults (0 success, 1 = failure from script) |

Use the same `.intunewin`; no edits needed. How the scripts handle this mode (v3.1.0):
- Intune stores the uploaded script **outside** the package, so `$PSScriptRoot` is not the content folder. The scripts search `$PSScriptRoot` **and** the current directory, which is the unpacked `.intunewin`, for `APD_5*_T20II.exe`.
- If Intune runs the script in 32-bit PowerShell, the script relaunches itself in 64-bit and keeps the content folder as its working directory. If it can't relaunch (no script path), it falls back to `sysnative\pnputil.exe`.
- Both scripts are about 10 KB and ASCII-only, well under the 50 KB script limit.
- The log records `PSCommandPath`, `CWD` and bitness on every run, so you can confirm which mode ran.
- The copies bundled inside the `.intunewin` are only used by Method A. With Method B, **re-upload the .ps1** in the app whenever you change a script. Updating the package alone won't update the uploaded script.

**Requirements:** 64-bit, Windows 10 2004+ (`pnputil /remove-device` needs 2004+)

**Detection:** Custom script â†’ `Detect-EpsonTMT20II.ps1`
- Run as 32-bit on 64-bit clients: **No**
- Enforce signature check: **No**

**Supersedence:** supersede the old *Epson TM-T20II Receipt Printer Driver* (v2) app with **Uninstall previous version = No**. The v3 install script removes the old `USB001` queues itself.

**Assignments:** *Available* to the service-desk device/user group (Company Portal); *Required* for known receipt-printer PCs (for example, Mailroom).

## Validation on a pilot PC

Run as SYSTEM to match Intune (Sysinternals PsExec):

```powershell
psexec -s -i "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
# in the SYSTEM window, from the Source folder:
.\Install-EpsonTMT20II.ps1; "exit: $LASTEXITCODE"
```

Check the result:

```powershell
Get-Printer | Where-Object DriverName -eq 'EPSON TM-T20II Receipt5' | Format-Table Name, PortName, PrinterStatus
Get-PrinterPort | Where-Object Name -like 'ESDPRT*' | Format-Table Name, Description, PortMonitor
Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\EPSON Port Handler Monitor'
Get-ItemProperty 'HKLM:\SOFTWARE\UMDLibraries\Intune\EpsonTMT20II-APD'
Get-Service | Where-Object DisplayName -like '*EPSON*' | Format-Table Name, DisplayName, Status
& .\Detect-EpsonTMT20II.ps1; "detect exit: $LASTEXITCODE"      # expect text + 0
```

Expected: queue `EPSON TM-T20II Receipt5` on `ESDPRT001`, which matches the working manual setup. Print a test page:

```powershell
Invoke-CimMethod -InputObject (Get-CimInstance Win32_Printer -Filter "Name='EPSON TM-T20II Receipt5'") -MethodName PrintTestPage
```

Uninstall test: `.\Uninstall-EpsonTMT20II.ps1` â†’ detection should then exit 1 with no output.

## Troubleshooting

| Check | Where |
|---|---|
| Install / uninstall log | `C:\ProgramData\EpsonTMT20II\Install.log`, `Uninstall.log` |
| Intune agent log | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload.log` (older builds: `IntuneManagementExtension.log`) |
| Epson setup log | `Setup.log` under `%ProgramFiles(x86)%\EPSON\EPSON Advanced Printer Driver 5\` or `C:\Windows\Temp` |

- **Installed, but no printer appears:** the TM-T20II was not plugged in. Plug it in and the queue appears on `ESDPRT###` within about 10 seconds.
- **Printer plugged in during install but no ESDPRT queue:** the script re-enumerates the device automatically. If that fails (it logs a WARN), unplug and replug the USB cable, or reboot.
- **Queue is on `USB001` instead of `ESDPRT`:** PCS isn't running or APD isn't installed. Rerun the install from Company Portal.
- **Manual fix-up:** Printer properties â†’ Ports â†’ check `ESDPRT001 â€“ USB TM-T20II`.

## Security notes
- The installer is Authenticode-signed by Seiko Epson. `Build-IntunePackage.ps1` refuses to package it if the signature isn't valid.
- **Print spooler:** APD adds a third-party port monitor DLL loaded into `spoolsv.exe` (SYSTEM). Watch CrowdStrike Falcon on the pilot for detections on `spoolsv.exe` loading Epson DLLs. It is signed and normally clean, but spooler changes are a common place for alerts.
- **Network:** `pcs.Setting` enables PCS TCP communication on **port 2291**. Check `Get-NetTCPConnection -LocalPort 2291 -State Listen` on the pilot. If it listens on `0.0.0.0`, Rapid7 InsightVM will report it. Block inbound TCP 2291 with the Intune firewall policy (it's only needed for Epson network printers, not USB).
- Nothing in these scripts uses credentials.

## Rollback
Assign the uninstall. `Uninstall-EpsonTMT20II.ps1` runs Epson's `/s /uninstall` and removes the driver, the driver-store package, and the sentinel. The legacy v2 package still exists in `..\TM-T20\` if you need to fall back.
