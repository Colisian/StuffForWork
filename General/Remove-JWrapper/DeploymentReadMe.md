# JWrapper / SimpleHelp Removal — Intune Deployment Guide

## Files Included

| File | Purpose |
|---|---|
| `Remove-JWrapperSimpleHelp.ps1` | Main remediation script (run as SYSTEM) |
| `Detect-JWrapperSimpleHelp.ps1` | Intune detection rule script |

---

## Intune Deployment Options

### Option A — PowerShell Script (Simplest, no detection)

1. Intune > Devices > Scripts > **Add > Windows 10 and later**
2. Upload `Remove-JWrapperSimpleHelp.ps1`
3. Settings:
   - Run this script using the logged on credentials: **No**
   - Enforce script signature check: **No** (or sign it with your UMD cert)
   - Run script in 64-bit PowerShell: **Yes**
4. Assign to **All Devices** or a targeted group

> ⚠️ Script deployments run once and don't re-run unless re-assigned.
> Use Option B for persistent compliance enforcement.

---

### Option B — Win32 App (Recommended — supports detection + re-run)

#### Step 1: Package with IntuneWinAppUtil

```
IntuneWinAppUtil.exe `
  -c C:\Packages\JWrapperRemoval\ `
  -s Remove-JWrapperSimpleHelp.ps1 `
  -o C:\Packages\Output\
```

#### Step 2: Create Win32 App in Intune

- **App type**: Windows app (Win32)
- **Install command**:
  ```
  powershell.exe -ExecutionPolicy Bypass -NonInteractive -File Remove-JWrapperSimpleHelp.ps1
  ```
- **Uninstall command** (placeholder):
  ```
  cmd.exe /c echo "N/A"
  ```
- **Install behavior**: System
- **Device restart behavior**: No specific action
- **Return codes**: 0 = Success

#### Step 3: Detection Rule

- Rule type: **Custom detection script**
- Upload: `Detect-JWrapperSimpleHelp.ps1`
- Run script as 32-bit: **No**

#### Step 4: Assignment

- Assign to **All Devices** as **Required**

---

## Log Location

```
C:\ProgramData\UMDLibrariesIT\Logs\Remove-JWrapperSimpleHelp_<timestamp>.log
```

Collect via Intune > Devices > Diagnostics, or ingest into your SIEM.

---

## What the Script Removes

| Artifact Type | Details |
|---|---|
| Processes | Any running JWrapper/SimpleHelp binaries |
| Services | `JWrapper*`, `SimpleHelp*` |
| Scheduled Tasks | Any task matching those name patterns |
| Firewall Rules | Inbound/outbound rules matching those patterns |
| Registry Keys | Uninstall keys + Run key entries |
| Directories | All known install paths under ProgramData, Program Files |

---

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Clean / Remediated successfully |
| 1 | Error during remediation — check log |