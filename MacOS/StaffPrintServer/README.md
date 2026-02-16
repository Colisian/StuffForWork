# Staff Print Server Scripts (macOS)

This folder contains Jamf-ready shell scripts for installing and uninstalling staff printers on macOS.

## Known-Good Checklist (Quick Validation)

Run this checklist before large deployments:

1. Canon UFR II driver package is installed on target Macs.
2. Script `PRINTER_URI` matches intended protocol (`lpd://` or `smb://`).
3. If using `lpd://`, Windows Print Server has `LPDSVC` installed and running.
4. Print Server is listening on TCP `515` (true `:515`, not `:515xx`).
5. Firewall/ACL allows inbound TCP `515` to the Print Server.
6. Queue name in URI exactly matches server queue name (case and spelling).
7. From a test Mac, `nc -vz -G 3 <print-server> 515` succeeds (for LPD).
8. Jamf policy order is correct: driver package first, install script second.
9. Script runs as root (Jamf policy context) and logs to `/var/log/umd_staff_printer_install.log`.
10. After install, `lpstat -p <QUEUE> -l` and `lpstat -v <QUEUE>` show expected values.

## Files in this folder

- `MCK/MCK_4F_PR2.sh`: Install McKeldin 4th Floor Printer 2
- `MCK/UNINSTALL_MCK_4F_PR2.sh`: Remove McKeldin 4th Floor Printer 2
- `PAL/PAL_1F_PR1.sh`: Install PAL 1st Floor Printer 1
- `PAL/UNINSTALL_PAL_1F_PR1.sh`: Remove PAL 1st Floor Printer 1

## How the install script works

The install scripts follow this flow:

1. Enable strict shell behavior (`set -e`, `set -u`, `set -o pipefail`).
2. Define printer-specific values:
   - `PRINTER_NAME`
   - `PRINTER_DESC`
   - `PRINTER_LOC`
3. Define shared values:
   - `PRINT_SERVER`
   - `PRINTER_URI` (for example `lpd://LIBRPS403v.ad.umd.edu/MCK_4F_PR2`)
   - Canon PPD filename/path
4. Log all output to `/var/log/umd_staff_printer_install.log`.
5. Validate root privileges (Jamf runs scripts as root).
6. Ensure CUPS is running.
7. Verify Canon UFR II PPD exists and is readable.
8. Remove any existing local printer with the same CUPS queue name.
9. Create printer with `lpadmin` using the URI and PPD.
10. Apply basic options:
    - `printer-is-shared=false`
    - `printer-error-policy=retry-job`
11. Verify printer exists in CUPS with `lpstat`.

## How the uninstall script works

The uninstall scripts:

1. Validate root privileges.
2. Check whether the printer exists in CUPS.
3. Remove it with `lpadmin -x`.
4. Verify removal.

## Jamf deployment pattern

Typical Self Service policy:

1. Add Canon UFR II driver package first.
2. Add the install script second.
3. Scope to staff devices/groups.
4. Optional separate Self Service policy for uninstall script.

## Print Server requirements for LPD (`lpd://`)

If script URI uses `lpd://`, the Windows Print Server must have LPD enabled and listening on TCP 515.

### 1) Install and start LPD service on server

Run on the print server (PowerShell as admin):

```powershell
Install-WindowsFeature Print-LPD-Service
Set-Service -Name LPDSVC -StartupType Automatic
Start-Service -Name LPDSVC
Get-Service LPDSVC
```

Expected result: `LPDSVC` exists and is running.

### 2) Confirm TCP 515 is listening

```powershell
Get-NetTCPConnection -LocalPort 515 -State Listen
netstat -ano | findstr /R /C:":515 .*LISTENING"
```

Important: do not treat `:51552` (or other ports starting with 515) as port 515.

### 3) Allow LPD through firewall/network ACLs

```powershell
Get-NetFirewallRule -DisplayName "*LPD*" | Format-Table DisplayName,Enabled,Direction,Action
```

If needed, create/enable inbound allow rule for TCP 515.

### 4) Verify LPD queue name

The queue in the URI must match what LPD exposes on the server.  
Example:

- Script URI: `lpd://LIBRPS403v.ad.umd.edu/MCK_4F_PR2`
- Queue name expected by server: `MCK_4F_PR2`

If the name does not match exactly, jobs may submit but never print.

## Client-side validation from macOS

```bash
nc -vz -G 3 LIBRPS403v.ad.umd.edu 515
lpstat -p MCK_4F_PR2 -l
lpstat -v MCK_4F_PR2
```

If port 515 fails but 445/139 succeed, SMB is reachable but LPD is still blocked/unavailable.

## SMB fallback option

If your environment does not support LPD reliably, use SMB URI instead:

- `smb://LIBRPS403v.ad.umd.edu/<QUEUE_NAME>`

In that case, ensure comments and deployment docs state SMB (not LPD) to avoid confusion.
