---
title: Epson TM-T20II Receipt Printer – Intune Silent Deployment (APD5 Copy Installation)
tags: [intune, win32, printer, epson, runbook]
version: 4.0.0
date: 2026-09-28
author: Oji
---

# Epson TM-T20II Receipt Printer – Intune Silent Deployment (v4)

## Summary

The TM-T20II only prints reliably on the **`ESDPRT001` – "USB TM-T20II"** port. That port belongs to Epson's **EPSON Port Handler Monitor**, so the standard [[Printer Deployment]] flow can't create it. That flow is `pnputil` → `Add-PrinterDriver` → `Add-PrinterPort` → `Add-Printer` from `printers.csv`, and `Add-PrinterPort` only makes TCP/IP, LPR and local ports.

Epson's supported silent method is **Copy Installation** (*APD5 Install Manual rev G*, chapter 3, pp. 39–46):

```
APD_513_T20II.exe /s /f1"<full path>\<script>.inf" /rN
```

The **script `.inf`** plays the role of `printers.csv`. It's exported **once** from a reference PC where the printer works, and it contains the printer queue, the ESDPRT port and the driver settings. Every PC then gets that same working setup silently.

| Standard flow ([[Printer Deployment]]) | This package |
|---|---|
| `printers.csv` (Name, DriverName, PortAddress) | Epson copy script `CopyScript\*.inf` |
| `pnputil /a` + `Add-PrinterDriver` | `APD_513_T20II.exe /s /f1"…"` installs driver + port monitor + service |
| `Add-PrinterPort` (TCP/IP) | ESDPRT001 created by the copy install |
| `Add-Printer` | Queue created by the copy install |
| `Detection.ps1` checks printer names | `Detect-EpsonTMT20II.ps1` checks sentinel + driver + monitor + ESDPRT queue |
| `c:\windows\temp\printer_install.log` | `C:\ProgramData\EpsonTMT20II\Install.log` |

### History
- **v2 (driver only):** the printer landed on `USB001`; detection needed the printer plugged in.
- **v3 (`/s`):** Epson returned **3 = "Specified command option cannot be used."** `/s` alone is not valid, so nothing was installed.
- **v4 (this):** documented `/s /f1"script"` copy installation.

---

## One-time: create the copy script on a reference PC

Use a **64-bit** PC where APD 5.13 was installed **manually through the Epson installer**, and where the printer is on `ESDPRT001` and prints. Epson won't create a copy script on a PC that was itself set up by copy installation.

1. Log in as an admin and confirm the printer prints a test page on port `ESDPRT001`.
2. **Start → EPSON Advanced Printer Driver 5 → Register, Change and Delete EPSON TM Printer**
3. Menu **Copy Installation → Create**
4. Copy Installation Package Type: **Copy data file only** (this writes the script `.inf`)
5. Printer to be copied: **uncheck "All Registered Printers"** and select only **EPSON TM-T20II Receipt5**
6. Save Directory: Browse to a folder → **Create** → OK → OK
7. Put the resulting `.inf` file in `TM-T20II-APD\CopyScript\` in this repo. There must be exactly one file.

> The script is tied to APD **5.13** and **64-bit**. If you update the APD package, re-export the script with the new version (Epson results 6/8/9 mean the script and installer don't match).

## Build

```powershell
cd "…\StuffForWork\General\RecepitPrinterDeployment\TM-T20II-APD"
.\Build-IntunePackage.ps1
```

This checks the Epson signature, bundles `APD_513_T20II.exe`, both scripts and the copy `.inf`, and writes `Work\Intune\2-IntuneApps\EpsonTMT20II-APD\Output\Install-EpsonTMT20II.intunewin`. It refuses to build without the copy script.

## Intune Win32 app

| Setting | Value |
|---|---|
| Installer type | **PowerShell script** (upload method) |
| Install script | `Install-EpsonTMT20II.ps1` |
| Uninstall script | `Uninstall-EpsonTMT20II.ps1` |
| Install behavior | **System** |
| Restart behavior | No specific action (scripts pass `/rN`) |
| Requirements | 64-bit, Windows 10 1903+ |
| Detection | Custom script `Detect-EpsonTMT20II.ps1`, run as 32-bit: **No** |
| Supersedence | Supersede the v2 app, *Uninstall previous* = **No** (the script cleans up v2 itself) |

Command-line alternative: `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-EpsonTMT20II.ps1` (and the same with `Uninstall-EpsonTMT20II.ps1`).

> With the upload method, **re-upload the .ps1 files** whenever they change. Rebuilding the `.intunewin` alone doesn't update them.

## What the install script does
1. **Exits 0** if the sentinel and an ESDPRT queue already exist.
2. **Clears the things Epson refuses to install over:**
   - removes existing `EPSON TM-T20II Receipt5` queues (result **4**, "printer already installed");
   - silently uninstalls an existing APD (result **-3**, "already installed");
   - removes the v2 driver-only install.
3. **Runs** `APD_513_T20II.exe /s /f1"<script.inf>" /rN` and translates Epson's result code into plain text in the log.
4. **Verifies** a queue exists on `ESDPRT###`, then writes the sentinel. Anything else exits 1, so Intune shows the failure.

## Epson result codes (manual p.46)

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Needs admin / low disk |
| 2 | Script file not found |
| 3 | Invalid command option (this was v3's `/s`) |
| 4 | Printer already installed – uninstall the printer first |
| 5 | Newer version installed |
| 6 / 8 / 9 | Script and installer package/version mismatch |
| 7 | Script bitness doesn't match the OS |
| -3 | APD5 already installed |
| -1 | Files in use / failed |
| 1151 | OS not supported |

Epson's own log: `C:\ProgramData\EPSON\EPSON Advanced Printer Driver 5\CopyInstallLog\CopyInstallLog.txt`. The install script copies its tail into `Install.log`.

## Pilot validation

```powershell
# as SYSTEM, from the unpacked Source folder
psexec -s -i "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
.\Install-EpsonTMT20II.ps1; "exit: $LASTEXITCODE"

Get-Printer | Where-Object DriverName -eq 'EPSON TM-T20II Receipt5' | Format-Table Name, PortName, PrinterStatus
Get-PrinterPort | Where-Object Name -like 'ESDPRT*' | Format-Table Name, Description
& .\Detect-EpsonTMT20II.ps1; "detect exit: $LASTEXITCODE"      # expect text + 0
Invoke-CimMethod -InputObject (Get-CimInstance Win32_Printer -Filter "Name='EPSON TM-T20II Receipt5'") -MethodName PrintTestPage
```

Uninstall test: `.\Uninstall-EpsonTMT20II.ps1`. Detection should then exit 1 with no output.

## Troubleshooting
- **Diagnostics:** run `Get-EpsonTMT20IIDiag.ps1` (read-only) → `C:\ProgramData\EpsonTMT20II\Diag-<PC>-<time>.txt`
- **Logs:** `Install.log`, `Uninstall.log` in `C:\ProgramData\EpsonTMT20II\`, plus Epson's `CopyInstallLog.txt`
- **Intune agent log:** `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload.log`

## Security notes
- The Epson installer is Authenticode-signed (Seiko Epson). The build refuses an invalid signature.
- APD adds a port monitor DLL to `spoolsv.exe` and the Port Communication Service. Watch CrowdStrike on the pilot.
- PCS may listen on **TCP 2291** (`pcs.Setting`). Check with `Get-NetTCPConnection -LocalPort 2291 -State Listen`. Block inbound via the Intune firewall policy if it's exposed; USB printing doesn't need it.
- The copy script holds printer settings only, with no credentials, so it's safe to commit.
