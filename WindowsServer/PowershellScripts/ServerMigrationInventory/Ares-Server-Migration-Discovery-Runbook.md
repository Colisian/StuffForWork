---
title: Ares Course Reserves Server Migration Discovery Runbook
author: Colisian (cmcleod1@umd.edu)
date: 2026-08-30
version: 2.0
tags:
  - ares
  - windows-server
  - migration
  - aws
  - iis
  - sql-server
---

# Ares Course Reserves Server Migration Discovery Runbook

## Purpose

Use the general `Get-WindowsServerMigrationInventory.ps1` scanner with `-ApplicationProfile Ares` to document the current Ares server before building or cutting over to a replacement. The script is discovery-only: it does **not** repair Windows Update, back up or modify SQL Server, stop services, copy application data, change the firewall, export private keys, or expose database rows.

The result is a timestamped evidence folder containing:

- `Windows-Server-Migration-Inventory.md` — readable migration summary and checklist with Ares profile findings.
- Detailed CSV files for software, services, IIS, SQL, ports, firewall, tasks, certificates, permissions, storage, and update events.
- `Inventory.json` — structured snapshot suitable for comparison or future automation.
- `Evidence-SHA256.csv` — integrity hashes for the evidence files.
- An optional ZIP archive.

> [!warning] Handle as sensitive operational data
> Password-, secret-, token-, and key-like values are redacted, and configuration contents are not copied. Even so, the evidence contains hostnames, IP addresses, service accounts, paths, certificate metadata, and security policy. Keep it in an access-controlled UMD location and redact it before sending to Atlas or attaching it to SysAid.

## Known UMD environment

| Environment | Host | Private IP | DNS | Purpose |
|---|---|---|---|---|
| Current PROD | `LIBRWS020V` | `10.126.5.109` | `coursereserves.umd.edu` | Current Ares production server |
| Existing TEST | `LIBRWS020TV-01` | `10.126.4.87` | `libarestest.umd.edu` | Ares test target |

Production systems use the `10.126.5.x` subnet; test systems use `10.126.4.x`. Use private IP addresses in application/database connection strings. Do not assign the existing production address or enable production automation on the replacement until the approved cutover step.

## Vendor constraints to confirm before building

Atlas’s current documentation says a self-hosted migration should begin with the **same Ares version** on the new and old servers; upgrade Ares only after the migration. Atlas also warns that a self-performed migration requires comfort with SQL, IIS, Windows permissions, and downtime coordination, and offers a paid migration service. See [Migrating an Ares Database](https://support.atlas-sys.com/hc/en-us/articles/360011923193-Migrating-an-Ares-Database).

Atlas’s current [Installing the Ares Server](https://docs.atlas-sys.com/ares/installing-and-updating/installing-the-ares-server) page confirms that the server installer deploys the database, services, web pages, and supporting files; documents `C:\Ares`, `C:\AresData`, `C:\Ares\Web\WebPages`, and `C:\Ares\AresDocs` as defaults; and calls out separate read/write permissions for `PublicDocs` and `TempUpload`. Those items are built into the script’s Ares profile.

As currently documented for Ares 5.0, Atlas supports Windows Server 2016/2019/2022 Desktop Experience, full SQL Server rather than SQL Express, mixed-mode SQL authentication, IIS 7.5 or later, .NET Framework 4.6.2 or newer, and the ASP.NET Core 8 Hosting Bundle for the Ares API. Confirm the exact support matrix with Atlas before selecting Windows Server 2025 or a newer SQL release. See [Ares 5.0 hardware and software requirements](https://support.atlas-sys.com/hc/en-us/articles/360049249374-Hardware-and-Software-Requirements-for-Version-5-0).

> [!tip] Recommended target baseline
> Unless Atlas confirms a newer supported platform, use Windows Server 2022 Desktop Experience and a supported full SQL Server edition. Do not use SQL Express. Obtain the matching Ares server installer directly from Atlas and schedule migration/update work during Atlas support hours.

## Phase 1 — Run the discovery inventory

### 1. Prepare a secure working folder

Copy this folder to the current Ares server, for example:

```text
C:\Temp\AresServerMigration
```

The default output is created beside the script. To write directly to an approved secured volume, use `-OutputRoot`.

### 2. Use elevated Windows PowerShell

Use **Windows PowerShell 5.1 as Administrator** for the authoritative run. PowerShell 7 can run most of the script, but the in-box IIS `WebAdministration` provider is most reliable in Windows PowerShell 5.1.

First perform a shorter validation:

```powershell
Set-Location -LiteralPath 'C:\Temp\AresServerMigration'
.\Get-WindowsServerMigrationInventory.ps1 -ApplicationProfile Ares -Quick -Verbose
```

Expected result: an object showing `ReportPath`, `EvidenceFolder`, `WarningCount`, and `Elevated = True`. Quick mode intentionally reports warnings for skipped SQL, event-log, and recursive filesystem collection.

Then run the full inventory:

```powershell
Set-Location -LiteralPath 'C:\Temp\AresServerMigration'
.\Get-WindowsServerMigrationInventory.ps1 -ApplicationProfile Ares -CreateArchive -Verbose
```

If local execution policy prevents launching the file, use the one-time process-level wrapper without changing machine policy:

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File '.\Get-WindowsServerMigrationInventory.ps1' -ApplicationProfile Ares -CreateArchive -Verbose
```

### 3. Optional individual file inventory

The normal full run reports counts and sizes by migration root and hashes configuration artifacts, but it does not list every Ares document filename. This protects patron/request metadata and keeps the collection manageable.

Only when an individual file manifest is operationally necessary:

```powershell
.\Get-WindowsServerMigrationInventory.ps1 `
    -ApplicationProfile Ares `
    -IncludeFileInventory `
    -MaxFileRecords 200000 `
    -CreateArchive `
    -Verbose
```

To hash every inventoried file as well, add `-IncludeFileHashes`. Expect substantial disk I/O and runtime; coordinate with operations and CrowdStrike monitoring before using it on a busy production server.

### 4. Validate the evidence

```powershell
$evidenceFolder = Get-ChildItem -LiteralPath '.\Server-Migration-Inventory' -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

Test-Path -LiteralPath (Join-Path $evidenceFolder.FullName 'Windows-Server-Migration-Inventory.md')
Get-Content -LiteralPath (Join-Path $evidenceFolder.FullName 'Inventory.json') -Raw |
    ConvertFrom-Json |
    Select-Object -ExpandProperty Metadata

Import-Csv -LiteralPath (Join-Path $evidenceFolder.FullName 'Evidence-SHA256.csv') |
    Select-Object FileName, SHA256
```

Success criteria:

- `Elevated` is `True`.
- The Markdown report opens and identifies the correct production host.
- SQL metadata identifies the actual Ares database (the UMD client configuration has used database name `Ares`, while Atlas defaults may use `AresData`).
- IIS sites/bindings, Ares/Atlas services, migration roots, and recent backup history are populated.
- Collection warnings are understood and either resolved with a rerun or recorded as manual follow-up.

## Phase 2 — Review the critical evidence

### SQL Server and Ares database

Atlas calls the SQL database the most crucial and least replaceable Ares component. Review:

- `SQL-Instances.csv` — edition, exact build, authentication mode, and collation.
- `SQL-Databases.csv` — Ares database name, state, recovery model, compatibility, and size.
- `SQL-DatabaseFiles.csv` — MDF/NDF/LDF paths and sizing.
- `SQL-BackupHistory.csv` — most recent full/differential/log backup evidence.
- `SQL-AgentJobs.csv` — backup and maintenance job state/results.
- `SQL-DatabaseTriggers.csv` — Ares database triggers that may include site customizations.
- `SQL-AresPathSettings.csv` — allow-listed path/URL/server customization values.

Atlas specifically advises using a native full database backup and restore, not DTS transfer or direct copying of live MDF/LDF files. See [Setting up Microsoft SQL Server database backups](https://docs.atlas-sys.com/docs/ares/database/setting-up-microsoft-sql-server-database-backups).

> [!danger] Inventory is not a backup
> Before cutover, create a final native full backup, copy it off the old host, restore it to a test instance, run `DBCC CHECKDB`, and perform Ares application tests. Do not treat a backup as proven until it restores successfully.

Atlas’s standard migration instructions also call for repairing the database user-to-login mapping after restore. Have the DBA verify the correct login and database name rather than blindly running a copied command, especially because UMD may use customized names or credentials.

### Ares application files

Review `MigrationRoots.csv`, `ConfigurationFileHashes.csv`, and `PathPermissions.csv`. Atlas documents these common locations, but customization keys and IIS data may point elsewhere:

- Ares application: `C:\Ares`
- Database/backup location: `C:\AresData`
- Web content: commonly `C:\inetpub\wwwroot\Ares` or `C:\Ares\Web\WebPages`
- Electronic documents: commonly `C:\Ares\AresDocs`
- Print/email templates: commonly `C:\Ares\Print`
- Database alias files such as `logon.dbc`
- Add-ons, DLLs, logs, imports/exports, and locally customized scripts

Atlas identifies `AresPhysicalDocPath` and `TempUploadPath` as important customization values and requires appropriate IIS identities to read the relevant content. See [Ares server configuration and permissions](https://docs.atlas-sys.com/ares/installing-and-updating/server-configuration-and-permissions).

Do not send DBC/config contents through email or a ticket. Some legacy database alias/configuration formats can contain SQL authentication material. Move required secrets through an approved secure method and rotate them during migration when practical.

### IIS and TLS

Review all `IIS*.csv` files and `Certificates.csv`:

- Sites, applications, virtual directories, and physical paths
- Application pool runtime, pipeline, identity, bitness, and start mode
- HTTP/HTTPS bindings, host headers, SNI flags, certificate thumbprints, and expiry
- Anonymous/basic/Windows/client-certificate authentication state
- Installed IIS role services in `WindowsFeatures.csv`
- ACLs for `IIS_IUSRS`, application-pool identities, service identities, and operator groups

Atlas says IIS Metabase Compatibility is required for the installer and documents the needed IIS/.NET configuration in [Internet Information Services](https://docs.atlas-sys.com/ares/installing-and-updating/internet-information-services).

For `coursereserves.umd.edu`, use the approved InCommon/Sectigo **Replace** workflow rather than Renew, install the server certificate through the approved secure process, and include the `USERTrust RSA` intermediate. The inventory records certificate metadata but never exports a private key.

### Ports and connectivity

Review `ApplicationPortReview.csv`, `ListeningEndpoints.csv`, and `FirewallRules.csv`. Atlas currently documents these common requirements in [Inbound and Outbound Ports](https://docs.atlas-sys.com/ares/installing-and-updating/inbound-and-outbound-ports):

| Function | Typical port | Direction from Ares role | Guidance |
|---|---:|---|---|
| Patron web pages | TCP 443 | Inbound | Required; HTTPS preferred |
| Patron web pages | TCP 80 | Inbound | Optional redirect/nonsecure; avoid serving credentials over HTTP |
| SQL Server | TCP 1433 | Web/client to SQL | Required unless the SQL instance uses another static port |
| SMTP relay | TCP 25 | Outbound | Default only; confirm UMD relay and source-IP allow-list |
| LDAP/LDAPS | TCP 389/636 | Outbound | Optional; prefer LDAPS 636 |
| Atlas updater FTP | TCP 20/21 | Outbound | Vendor-documented; confirm whether the installed updater still needs it |
| Z39.50 | Site-specific | Outbound | Optional, OPAC-specific |
| PatronAPI | TCP 4500 typical | Outbound | Optional, site-specific |
| RDP | TCP 3389 | Inbound | Administration only; restrict to VPN/approved management ranges |

The script sees the host firewall and local listeners only. Separately inventory and approve:

- EC2 Security Groups and NACLs
- Route tables and subnet placement
- Campus/DIT firewall controls
- Load balancers, target groups, health checks, and TLS termination
- DNS and planned TTL changes
- SMTP relay source-IP restrictions
- Client, web, and integration source ranges

Do not reproduce broad legacy `Any`/`Any` rules just because they exist. Start with the required flows and least-privilege source/destination ranges, then document each exception.

### Services, scheduled work, and service identities

Review `Services.csv`, `ScheduledTasks.csv`, and `SQL-AgentJobs.csv` for:

- Atlas/Ares executables and exact versions
- Startup type and recovery behavior
- Service-account identity and local rights
- Scheduled file cleanup, imports/exports, backups, monitoring, and log jobs
- Working directories, command-line dependencies, network shares, and mapped paths

Do not copy passwords into scripts or the runbook. Prefer managed identities/gMSA where supported; otherwise store credentials in the approved secret system and rotate at cutover.

During production cutover, prevent both servers from running automated Ares jobs against the same production database. Atlas’s migration guidance specifically calls for disabling old services and taking the old database offline to prevent conflict.

### Security, monitoring, and backup agents

Confirm the replacement appears healthy in:

- CrowdStrike Falcon
- Rapid7 InsightVM
- AWS Systems Manager/SSM
- Central logging and alerting
- EC2/EBS backup policy and restore testing
- Uptime, TLS-expiry, service, disk, and application monitoring

Install/register fresh security agents. Do not clone old agent identities, certificates, or registration state. Coordinate large file hashing/copying and the first Rapid7 scan so expected activity does not obscure real detections.

## Phase 3 — Build and test the replacement

1. Confirm the target Windows/SQL/Ares versions and obtain the matching Ares installer from Atlas.
2. Build in the production subnet with a temporary private IP; do not reuse `10.126.5.109` during parallel testing.
3. Join `AD.UMD.EDU` in the approved server OU and apply the server security baseline.
4. Install current Windows patches, CrowdStrike, Rapid7, SSM, logging, backup, and monitoring.
5. Install required IIS roles, .NET/ASP.NET runtimes, full supported SQL Server, and matching Ares server components.
6. Recreate IIS, services, scheduled tasks, firewall rules, permissions, shares, and integrations from the reviewed evidence—not by blindly cloning obsolete settings.
7. Restore a recent Ares backup in isolation and validate DB integrity, login mapping, custom triggers, SQL Agent jobs, and customization paths.
8. Pre-copy web pages, templates, add-ons, and AresDocs content through an access-controlled transfer channel.
9. Run the inventory script on the replacement and compare both evidence folders.

### Basic old/new comparison commands

```powershell
$oldFolder = 'D:\MigrationEvidence\OldServer'
$newFolder = 'D:\MigrationEvidence\NewServer'

$oldServices = Import-Csv -LiteralPath (Join-Path $oldFolder 'Services.csv')
$newServices = Import-Csv -LiteralPath (Join-Path $newFolder 'Services.csv')

Compare-Object `
    -ReferenceObject ($oldServices | Select-Object Name, StartMode, StartName, PathName) `
    -DifferenceObject ($newServices | Select-Object Name, StartMode, StartName, PathName) `
    -Property Name, StartMode, StartName, PathName

$oldFeatures = Import-Csv -LiteralPath (Join-Path $oldFolder 'WindowsFeatures.csv')
$newFeatures = Import-Csv -LiteralPath (Join-Path $newFolder 'WindowsFeatures.csv')

Compare-Object `
    -ReferenceObject $oldFeatures `
    -DifferenceObject $newFeatures `
    -Property Name, InstallState
```

Differences are expected where the new design intentionally removes obsolete software, narrows firewall rules, changes paths, or modernizes service identities. Record each accepted difference and its owner.

## Phase 4 — Cutover and rollback gates

### Before the outage

- [ ] Atlas support window and UMD owners are confirmed.
- [ ] Change record, staff communication, outage window, and rollback decision time are approved.
- [ ] DNS TTL is lowered in advance if DNS will change.
- [ ] Test restore and application tests pass on the replacement.
- [ ] Final database and filesystem copy commands are peer-reviewed.
- [ ] New host has healthy CrowdStrike, Rapid7, SSM, logging, backup, and monitoring coverage.
- [ ] Old-server rollback remains viable and no destructive cleanup is scheduled during the validation window.

### During cutover

- [ ] Stop patron/staff writes and confirm active users are out.
- [ ] Stop/disable old Ares services and scheduled automation in the approved order.
- [ ] Take the final native full SQL backup and verify completion.
- [ ] Complete the final file delta copy, including AresDocs/PDF content written since pre-copy.
- [ ] Restore/attach only through the DBA-approved native restore process.
- [ ] Verify SQL login-to-user mapping and enable only the intended new jobs/services.
- [ ] Change DNS/IP/load-balancer targets and required firewall allow-lists.

### Post-cutover tests

- [ ] Patron HTTPS access and certificate chain
- [ ] Patron authentication/SSO/LTI as applicable
- [ ] Course lookup and reserve-item access
- [ ] Staff Ares client/ODBC connection
- [ ] PDF/document delivery and upload/temp paths
- [ ] Email/SMTP delivery
- [ ] Scheduled processing, cleanup, imports/exports, and add-ons
- [ ] SQL full backup and off-host copy
- [ ] Application/IIS/SQL logs and Windows event logs
- [ ] CrowdStrike, Rapid7, SSM, backup, and monitoring health
- [ ] External integrations such as LDAP, LMS/LTI, Z39.50, PatronAPI, shares, and reporting

### Rollback trigger examples

- Database integrity or schema/login mapping cannot be validated.
- Patron/staff core workflows fail and cannot be corrected before the decision time.
- Documents are missing or ACLs prevent delivery/upload.
- TLS, authentication, SMTP, or critical integrations remain unavailable.
- Security/monitoring/backup coverage cannot be confirmed.

Rollback should reverse DNS/IP/load-balancer targeting, keep the new automation stopped, return the old database/server to the approved online state, and communicate status. The exact order must be finalized with Atlas and the DBA because writes occurring on both sides create data-divergence risk.

## Windows Update issue: preserve evidence before repair

The migration inventory collects recent warnings/errors from Windows Update, Servicing, Setup, System, and Application logs plus common pending-reboot indicators. Review `RecentWarningErrorEvents.csv` before attempting repairs.

Useful read-only checks on the old server:

```powershell
Get-ComputerInfo |
    Select-Object WindowsProductName, WindowsVersion, OsBuildNumber, OsHardwareAbstractionLayer

Get-HotFix |
    Sort-Object InstalledOn -Descending |
    Select-Object -First 20 HotFixID, Description, InstalledOn

Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-WindowsUpdateClient/Operational'
    Level   = 1, 2, 3
} -MaxEvents 100 |
    Select-Object TimeCreated, Id, LevelDisplayName, Message
```

Do not mix update-component reset, DISM repair, OS in-place repair, and Ares migration changes in one uncontrolled window. Diagnose the update code first, preserve a rollback path/snapshot per policy, and decide whether repairing the old host or accelerating the tested replacement carries less service risk.

## Completion criteria

The discovery phase is complete when:

- An elevated full evidence bundle exists for the current production server.
- SQL, IIS, Ares paths, permissions, services, firewall/listeners, scheduled work, certificates, and external dependencies have named owners.
- Every collection warning is resolved or has a documented manual validation.
- Atlas confirms the supported target and migration approach.
- A test restore and end-to-end application validation plan exists.
- Cutover, rollback, stakeholder communication, security coverage, and backup validation are approved.
