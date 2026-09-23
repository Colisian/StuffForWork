---
tags: [intune, printer, staff-printer, runbook, company-portal]
updated: 2026-09-22
---
# Staff Printers - Package & Deploy via Company Portal

Goal: each staff printer is a **self-service app in Company Portal**. Staff click Install. Intune installs the right driver automatically, then adds the printer machine-wide.

```
Company Portal (user clicks "Install")
   └─ Printer app  (e.g. "Printer - McKeldin - Graphics 6115 - Color (MCK_6F_PR4)")
        ├─ dependency: Staff Printer Driver - Canon Generic Plus UFR II   (auto, hidden)
        └─ Install-StaffPrinter.ps1 as SYSTEM -> TCP/IP port + printer for all users
```

## Key design decisions
| Decision | Why |
|---|---|
| **Available** assignment to a **user** group | Company Portal only lists apps that are assigned as Available. User-group targeting means the app follows the person to any Libraries PC. |
| Install behavior **System** (even though the assignment targets users) | This is supported: the user triggers the install and the Intune agent runs it as SYSTEM. The printer is local and machine-wide, so it needs admin rights and doesn't need the user's profile. *(The DIT guide says a user-targeted app needs User context. That only applies to its old per-user method.)* |
| Driver apps as **dependencies**, never assigned | Each driver is uploaded once. Intune installs it silently before the printer, and it never clutters Company Portal. |
| "Allow available uninstall" = **Yes** | Staff can remove a printer they no longer need, straight from Company Portal. |
| Requirement: **x64** | Both driver packages are x64 only. Arm64 devices would fail. |
| Friendly names: `Printer - <Location> - <Color/B&W> (<QUEUE>)` | Staff search by place, not by queue code. The queue code stays in brackets for the service desk. |

## One-time setup
1. **Company Portal category**: Intune admin center > **Apps > App categories** > *Create* > `Printers`.
2. **Staff user group**: pick or create an Entra group such as `LIBR-Staff-Users`, plus a small pilot group such as `LIBR-Printer-Pilot`.
3. **Icon** (optional but worth it): save a 512x512 PNG printer icon as `_Build\printer-icon.png` and use it for every printer app.
4. **IntuneWinAppUtil.exe**: download it from <https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool>, for example to `C:\Tools\`.

## Step 1 - Build packages
```powershell
cd "<repo>\Intune\StaffPrinter"
.\_Build\Build-StaffPrinterFolders.ps1                     # refresh folders from the master CSV
.\_Build\New-StaffPrinterPackages.ps1 -IntuneWinAppUtil C:\Tools\IntuneWinAppUtil.exe
# -> _Output\<NAME>.intunewin for every Ready printer + both driver apps
```

## Step 2 - Create the two driver apps (once)
Apps > Windows > Add > **Windows app (Win32)**. Use the settings in each `_Driver-*\README.md`.
- Name: `Staff Printer Driver - Canon Generic Plus UFR II` / `Staff Printer Driver - HP Universal Printing PCL 6`
- Detection: `Detect-PrinterDriver.ps1`
- **No assignments.**

> [!info] Installer type: PowerShell script (default) or command line
> Every Install/Uninstall script works both ways with no edits. On the **Program** tab, choose **PowerShell script** and upload the `.ps1` from the app's folder, with *Run as 32-bit* = No. Intune runs it with the package contents as its working folder, so `printer.csv` / `Driver\` are still found. The same `.intunewin` works for either method.
> When you change a script, **re-upload it on the Program tab**. With this method the copy inside the package is not the one that runs.

## Step 3 - Create each printer app
Use the settings from `<NAME>\README.md`. It has copy-paste values for Name, Description, commands, detection and dependency.
- **Dependencies** tab: add the matching driver app, with *Automatically install* = **Yes**.
- **Assignments**: **Available for enrolled devices** > pilot group first. Turn on "Allow available uninstall".
- Scope tag: LIBR.

> [!tip] 32 apps by hand is ~15 min each
> Once the first app is proven, the rest can be created by script with the `IntuneWin32App` PowerShell module (Microsoft Graph). The script would read the master CSV and set the name, description, commands, detection, dependency, category and assignment for all 32. This removes copy-paste errors. Signing in is delegated/interactive, so no secrets are stored.

## Step 4 - Pilot
1. Assign the driver app + 2-3 printer apps (ideally ones whose DNS already resolves, e.g. `HBK_2F_PR1`) as Available to `LIBR-Printer-Pilot`.
2. On a pilot PC: Company Portal > Printers > Install. Expect a few minutes; the driver installs first.
3. Verify:
   ```powershell
   Get-Printer | Where-Object PortName -like 'IP_*' | Format-Table Name, DriverName, PortName
   Get-PrinterDriver -Name 'Canon Generic Plus UFR II'
   Get-Content C:\ProgramData\StaffPrinters\*-Install.log -Tail 20
   Get-Content C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload.log -Tail 50   # IME side
   ```
4. Print a test page, then uninstall it from Company Portal and confirm the printer and its port are gone. The driver stays, which is expected.

## Step 5 - Roll out
- Add `LIBR-Staff-Users` to each app's Available assignment.
- **Optional Required push**: for a department that should always have its printer, add a **Required** assignment to that department's *device* group. Available and Required can coexist on the same app.

## Retiring the old print-server apps (important)
The old `StaffPrintServer` apps use `UNINSTALL_TEMPLATE.ps1`, which removes **all 32** print-server connections. It also checks for the short printer name first, so it could remove the new direct-IP printer that has the same name.
- **Recommended:** remove the old apps' assignments (stop offering them) at cutover. Users keep existing connections until they remove them or the server queues are deleted.
- **Supersedence** (new app supersedes old, "Uninstall previous version" = Yes) is only safe after the old uninstall is changed to remove **one** printer by its UNC name. As it stands, installing one new printer would wipe every old one.

## Updating later
| Change | Do this |
|---|---|
| Printer hostname / location | Edit master CSV > regenerate > repackage that printer > **upload new .intunewin + upload new detection script** to the same app |
| New driver version | Extract the new x64 zip into `_Driver-*\Driver\` > repackage the driver app > set `$MinimumVersion` in `Detect-PrinterDriver.ps1` so devices upgrade |
| New printer | Add a CSV row > regenerate > package > create the app |
