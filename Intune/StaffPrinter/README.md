---
tags: [intune, printer, staff-printer, runbook]
updated: 2026-09-22
---
# Staff Printers - Direct IP Deployment (Intune Win32)

Moves staff printers off the `LIBRPS403V` print server (per-user `\\server\queue` connections) to **machine-wide direct TCP/IP printers** that print straight to `<NAME>.resource.dyn.umd.edu:9100`. Based on the DIT *Printer Deployment* guide in `StaffPrinters\`, updated to fit how we deploy (one app per printer, bundled data file, custom detection, System context).

## Layout
```
StaffPrinter\
  _Build\
    StaffPrinters-DirectIP.csv      <- MASTER DATA (edit this)
    Build-StaffPrinterFolders.ps1   <- regenerates every printer folder from the CSV
    Get-StaffPrinterInventory.ps1   <- read-only: print-server truth + DNS + port 9100 check
    Template\                       <- shared Install/Uninstall scripts + detection template
  _Driver-CanonGenericPlusUFRII\    <- driver app (dependency) for 30 Canon printers
  _Driver-HPUniversalPCL6\          <- driver app (dependency) for HBK_4F_PR2, STM_1F_CIRC
  <PRINTER_NAME>\  x32              <- one Win32 app each (generated)
     Install-StaffPrinter.ps1, Uninstall-StaffPrinter.ps1, printer.csv, Detect-<NAME>.ps1, README.md
  StaffPrinters\                    <- DIT guide + inventory spreadsheet (reference)
  StaffPrintServer\                 <- old print-server apps (being replaced)
  _Build\DriverSource\              <- original vendor zips (kept OUT of the packages)
```

## Workflow
1. Fill gaps in `_Build\StaffPrinters-DirectIP.csv` (see `Status` / `Notes` columns).
2. `.\_Build\Get-StaffPrinterInventory.ps1 | Format-Table` - re-check DNS and port 9100.
3. `.\_Build\Build-StaffPrinterFolders.ps1` - regenerate folders.
4. Drivers are extracted: Canon Generic Plus UFR II v3.50 (`CNLB0MA64.INF` + `gpb0.cab`) and HP UPD PCL6 v8.2.0 (`hpcu360u.inf`). Package + create both driver apps. To update a driver later: extract the new x64 zip into `Driver\` (replace contents), bump the app version, re-upload.
5. For each printer whose Status is `Ready`: package it, create the app, add the driver app as a dependency, assign it to a pilot device group.

## Why System context (vs. the old User-context apps)
- A local TCP/IP printer created as SYSTEM is visible to **every** user on the device, and SYSTEM can see it, so detection is just `Get-Printer`. The old registry-hive detection workaround is no longer needed.
- No Point and Print, no print-server dependency, and no PrintNightmare driver-install restrictions for standard users.
- Trade-offs: jobs no longer pass through the server, so there is no central queue, job log or accounting. Each device needs a network path to the printer on 9100/TCP, plus 161/UDP SNMP for status and the Generic Plus "Get device info" feature.

## Status legend
| Status | Meaning |
|---|---|
| Ready | Data complete - OK to package. If the DDNS name doesn't resolve yet, install still succeeds (logs a warning) and printing starts once DNS exists |
| NeedsInfo | Data missing or conflicting - see Notes |
