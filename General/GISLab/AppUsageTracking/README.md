# GIS Lab Application Usage Tracking

Intune deployment package for collecting per-device launch counts and runtime
totals for selected Windows applications. The solution records aggregate
application usage only; it does not write usernames or command lines to the CSV.

## Table of Contents

- [[#Purpose]]
- [[#Package Contents]]
- [[#Intune Deployment]]
- [[#Data and Logs]]
- [[#Watch List]]
- [[#Verification]]
- [[#Pilot Test Matrix]]
- [[#Security and Privacy]]
- [[#Rollback]]

---

## Purpose
> [[#Table of Contents|↑ Back to TOC]]

The scheduled task reads new Windows Security events 4688 and 4689 every 15
minutes. It pairs process creation and termination events, maintains durable
state, and generates `usage.csv` for the endpoint.

The version 2 state file is the source of truth. If CSV replacement fails, the
next run regenerates the report without replaying already committed events.

---

## Package Contents
> [[#Table of Contents|↑ Back to TOC]]

| File | Purpose |
|---|---|
| `Setup-AppUsageTracking.ps1` | Installs, validates, and writes the detection sentinel |
| `Harvest-AppUsage.ps1` | Processes event data and generates the CSV |
| `AppUsageTracking-WatchList.txt` | Bundled executable-name configuration |
| `Detect-AppUsageTracking.ps1` | Intune custom detection script |
| `Uninstall-AppUsageTracking.ps1` | Removes the task and retains or purges data |

---

## Intune Deployment
> [[#Table of Contents|↑ Back to TOC]]

Package the entire directory so the installer can locate the harvester and
watch-list companion files.

```powershell
IntuneWinAppUtil.exe `
    -c .\AppUsageTracking `
    -s Setup-AppUsageTracking.ps1 `
    -o .\Output
```

Use these Win32 app commands:

```text
Install:
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup-AppUsageTracking.ps1

Uninstall, retain data:
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-AppUsageTracking.ps1

Uninstall, purge data:
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-AppUsageTracking.ps1 -PurgeData
```

Configure the app to install as **SYSTEM**, use the **64-bit PowerShell host**,
and upload `Detect-AppUsageTracking.ps1` as a custom detection script.

The setup script also supports Intune's pasted PowerShell installer method. Its
companion files must still be included in the unpacked package directory.

---

## Data and Logs
> [[#Table of Contents|↑ Back to TOC]]

| Path | Contents |
|---|---|
| `C:\ProgramData\LabUsage\usage.csv` | Human-readable aggregate report |
| `C:\ProgramData\LabUsage\state.json` | Atomic processing state and totals |
| `C:\ProgramData\LabUsage\Harvest-AppUsage.ps1` | Installed harvester |
| `C:\ProgramData\LabUsage\AppUsageTracking-WatchList.txt` | Installed watch list |
| `C:\ProgramData\UMDLibraries\AppUsage\AppUsageTracking-Setup.log` | Setup transcript |
| `C:\ProgramData\UMDLibraries\AppUsage\AppUsageTracking-Harvest.log` | Harvester transcript |
| `C:\ProgramData\UMDLibraries\AppUsage\AppUsageTracking-Uninstall.log` | Uninstall transcript |

The harvest log rolls to `.old` after it exceeds 1 MB.

---

## Watch List
> [[#Table of Contents|↑ Back to TOC]]

Edit `AppUsageTracking-WatchList.txt` before repackaging. Use one executable leaf
name per line. Matching is case-insensitive, blank lines are ignored, and lines
starting with `#` are comments.

Validate the executable names on the production GIS image before assignment.
For example, confirm the actual Tableau, MATLAB, Jupyter, and statistics-package
process names in Task Manager or with:

```powershell
Get-Process | Sort-Object ProcessName | Select-Object ProcessName, Id
```

---

## Verification
> [[#Table of Contents|↑ Back to TOC]]

Run these commands from an elevated PowerShell session:

```powershell
Get-ScheduledTask -TaskName 'LabAppUsageHarvester'
Get-ScheduledTaskInfo -TaskName 'LabAppUsageHarvester'

Get-ItemProperty 'HKLM:\SOFTWARE\UMDLibraries\LabAppUsageTracking'
Get-Content 'C:\ProgramData\LabUsage\state.json' -Raw | ConvertFrom-Json
Import-Csv 'C:\ProgramData\LabUsage\usage.csv' | Format-Table

Get-WinEvent -FilterHashtable @{
    LogName = 'Security'
    Id = 4688, 4689
    StartTime = (Get-Date).AddMinutes(-30)
} -MaxEvents 20
```

Launch and close one watched application, start the scheduled task manually,
and confirm its launch count and runtime increase only once:

```powershell
Start-ScheduledTask -TaskName 'LabAppUsageHarvester'
Start-Sleep -Seconds 10
Import-Csv 'C:\ProgramData\LabUsage\usage.csv' | Format-Table
```

---

## Pilot Test Matrix
> [[#Table of Contents|↑ Back to TOC]]

| Scenario | Expected result |
|---|---|
| Launch and normal exit | One launch; runtime approximates the session |
| Application spans two task runs | Runtime grows without double counting |
| Application runs longer than 24 hours | Runtime continues while the same process is active |
| Reboot or hard shutdown | Powered-off time is not credited |
| Security log is cleared | Collection restarts and writes a warning to the harvest log |
| CSV is open or temporarily locked | State remains correct; CSV regenerates on a later run |
| Harvester or watch list is modified | Intune custom detection returns noncompliant |
| Scheduled task fails | Setup withholds the registry detection sentinel |

Pilot on 2–5 representative GIS endpoints for several days before broad
assignment. Compare a small set of observed sessions with the CSV totals.

---

## Security and Privacy
> [[#Table of Contents|↑ Back to TOC]]

- The scheduled task runs as SYSTEM because reading the Security log requires
  elevated rights.
- Standard users receive read-only access to `C:\ProgramData\LabUsage`.
- The report contains application names, counts, durations, and timestamps; it
  does not contain usernames.
- Process auditing increases Security-log volume. Monitor log retention during
  the pilot so events are not overwritten between harvests.
- Do not use `-IncludeCmdLine` without security and privacy approval. Windows
  command-line audit data can contain filenames, tokens, or credentials even
  though this harvester does not export that field.

---

## Rollback
> [[#Table of Contents|↑ Back to TOC]]

The default uninstall removes the task and registry sentinel, but moves the data
directory to `C:\ProgramData\LabUsage.retained-<timestamp>`.

Process auditing remains enabled by default because another security product or
policy may depend on it. Use `-DisableAuditing` only after confirming that no
other control requires events 4688 and 4689. Use `-DisableCmdLine` separately if
this package previously enabled command-line auditing.
