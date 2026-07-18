# Disk Space Monitor

Daily scheduled task (SYSTEM) that emails an alert when free space on monitored drives drops below a threshold. Mail goes through an SMTP relay — **no credentials are stored in any script**.

## Components

| File | Purpose |
|---|---|
| `Invoke-DiskSpaceCheck.ps1` | The check itself. Reads `C:\ProgramData\DiskSpaceMonitor\config.json`, logs to `DiskSpaceMonitor.log` in the same folder, throttles repeat alerts. |
| `Install-DiskSpaceMonitor.ps1` | Copies the check script to `C:\Program Files\DiskSpaceMonitor`, writes the config, registers the scheduled task (daily, `StartWhenAvailable`). |
| `Uninstall-DiskSpaceMonitor.ps1` | Removes the task and both directories. |
| `Detect-DiskSpaceMonitor.ps1` | Intune Win32 detection script. |

## Manual install (elevated PowerShell)

```powershell
.\Install-DiskSpaceMonitor.ps1 `
    -EmailTo cmcleod1@umd.edu `
    -EmailFrom cmcleod1@umd.edu `
    -SmtpServer <relay-hostname> `
    -ThresholdGB 200 `
    -DriveLetters C
```

> **Confirm the relay hostname with DIT** before deploying. The default assumption is an internal relay accepting unauthenticated mail on port 25 from campus/library IP space. For an authenticated submission port instead, add `-SmtpPort 587 -UseSsl -CredentialXmlPath <path>` (see below).

## Intune Win32 packaging

```powershell
IntuneWinAppUtil.exe -c .\EmailNotification -s Install-DiskSpaceMonitor.ps1 -o .\Output
```

- **Install command:**
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File Install-DiskSpaceMonitor.ps1 -EmailTo cmcleod1@umd.edu -EmailFrom cmcleod1@umd.edu -SmtpServer <relay-hostname>`
- **Uninstall command:**
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File Uninstall-DiskSpaceMonitor.ps1`
- **Detection:** custom script → `Detect-DiskSpaceMonitor.ps1`
- **Install behavior:** System
- **Return codes:** 0 = success, 1 = failure (defaults are fine)

## Optional: authenticated relay

Only if the relay requires a login. The credential file is DPAPI-encrypted, meaning it can only be decrypted by the **same account on the same machine** — so it must be created as SYSTEM on the target box:

```powershell
# From an elevated prompt, using Sysinternals PsExec to get a SYSTEM shell:
psexec -s -i powershell.exe
# In the SYSTEM PowerShell window:
$cred = Get-Credential   # relay account
$cred | Export-Clixml -Path 'C:\ProgramData\DiskSpaceMonitor\smtp-credential.xml'
```

Then install with `-CredentialXmlPath 'C:\ProgramData\DiskSpaceMonitor\smtp-credential.xml'`. The file is useless if copied to another machine or read by another account.

## Verification

```powershell
# Task registered?
Get-ScheduledTask -TaskName 'Disk Space Monitor' | Select-Object TaskName, State

# Run the check on demand and watch the output:
Start-ScheduledTask -TaskName 'Disk Space Monitor'
Get-Content 'C:\ProgramData\DiskSpaceMonitor\DiskSpaceMonitor.log' -Tail 20

# Force an alert end-to-end: temporarily raise the threshold above current free space
# in C:\ProgramData\DiskSpaceMonitor\config.json, delete state.json, re-run the task,
# confirm the email arrives, then restore the threshold.
```

## Behavior notes

- **Throttling:** while a drive stays below threshold, alerts repeat at most once per `ReAlertHours` (default 24). Delete `C:\ProgramData\DiskSpaceMonitor\state.json` to reset.
- **Missed trigger:** `StartWhenAvailable` runs the check at next boot if the machine was off at the scheduled time.
- **Log rotation:** the transcript rotates to `.old` at 5 MB.
- **Security:** no secrets in scripts or in this repo. CrowdStrike may log the `powershell.exe -File` execution from Task Scheduler — expected and benign; the script path is a stable IOC-friendly location (`C:\Program Files\DiskSpaceMonitor`).
