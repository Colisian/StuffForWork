# Windows Server Migration Inventory

`Get-WindowsServerMigrationInventory.ps1` is a read-only discovery tool for documenting a Windows Server before an application or operating-system migration. Its default behavior is vendor-neutral. Optional application profiles add narrowly scoped vendor knowledge without removing the general Windows, IIS, SQL, firewall, service, storage, security, and update inventory.

## Recommended execution environment

Run from **64-bit Windows PowerShell 5.1 as Administrator** on the source server. PowerShell 7 can collect most evidence, but the in-box IIS `WebAdministration` provider is most reliable in Windows PowerShell 5.1.

The script writes evidence files only. It does not change server configuration, stop services, install software, repair Windows, copy application data, create SQL backups, or export certificate private keys.

## General Windows Server inventory

First perform a shorter validation run:

```powershell
.\Get-WindowsServerMigrationInventory.ps1 -Quick -Verbose
```

Then perform the full general inventory:

```powershell
.\Get-WindowsServerMigrationInventory.ps1 -CreateArchive -Verbose
```

The General profile inventories the entire server but does not assume which installed application, database, directory, or port is authoritative. Use the detailed CSVs to identify the workload, or supply custom selectors.

## Custom application inventory

```powershell
.\Get-WindowsServerMigrationInventory.ps1 `
    -ApplicationName 'Vendor Application' `
    -ApplicationRoot 'D:\VendorApp', 'E:\VendorData' `
    -DatabaseNamePattern '^Vendor(Db|Data)$' `
    -SqlServerInstance 'SQLHOST\INSTANCE' `
    -CreateArchive `
    -Verbose
```

| Parameter | Purpose |
|---|---|
| `-ApplicationName` | Friendly workload name in the Markdown and JSON reports; also used to match installed software and services. |
| `-ApplicationRoot` | One or more additional application/data roots to size, inspect for configuration-file metadata, and include in the ACL inventory. |
| `-DatabaseNamePattern` | PowerShell regular expression selecting SQL databases for trigger inventory. Without it, all non-system databases are used. |
| `-SqlServerInstance` | Optional local/remote SQL targets to query in addition to locally discovered instances. Uses current Windows integrated authentication only. |
| `-IncludeFileInventory` | Records individual filenames and metadata. Treat this as sensitive because names may contain operational/user identifiers. |
| `-IncludeFileHashes` | Adds SHA-256 for each inventoried file and implies `-IncludeFileInventory`; expect substantial I/O. |
| `-OutputRoot` | Writes the timestamped evidence folder under an approved secured location. |
| `-CreateArchive` | Creates a ZIP beside the completed evidence folder. |

## Ares Course Reserves profile

```powershell
.\Get-WindowsServerMigrationInventory.ps1 `
    -ApplicationProfile Ares `
    -CreateArchive `
    -Verbose
```

The Ares profile adds:

- Atlas/Ares software and service matching.
- Default application, SQL data, web-template, document, print, backup, `PublicDocs`, and `TempUpload` paths.
- Ares/AresData SQL database selection, triggers, and safe path/URL/server customization values.
- Atlas-documented Ares port review.
- Ares-specific migration and validation notes in the Markdown report.
- Separate ACL checks for document upload/delivery paths.

See `Ares-Server-Migration-Discovery-Runbook.md` for the UMD production/test context, Atlas guidance, test plan, cutover gates, and rollback considerations.

## Evidence produced

Each run creates `Server-Migration-Inventory\<HOST>-<TIMESTAMP>` containing:

- `Windows-Server-Migration-Inventory.md`
- `Inventory.json`
- `Evidence-SHA256.csv`
- Installed software, Windows roles/features, services, scheduled tasks, local users/groups, and hotfix CSVs
- Firewall rules, listening endpoints, network adapters, and optional profile-port review CSVs
- IIS sites, applications, virtual directories, pools, bindings, authentication, and certificate CSVs
- SQL instances, databases, files, latest backup history, Agent jobs, and database trigger CSVs
- ODBC system DSNs with secret-like values redacted
- Migration roots, top-level ACLs, shares, volume capacity, and configuration-file hashes
- Recent warning/error events from Windows Update, servicing, Setup, System, and Application logs

Empty CSV categories are omitted. Collection failures and permission gaps are recorded in the Markdown report and JSON rather than aborting unrelated discovery.

## Security handling

The evidence intentionally excludes database rows, configuration-file contents, certificate private keys, and password/token/key-like values. It still contains sensitive infrastructure details such as IP addresses, service identities, paths, firewall policy, process command lines, event messages, certificate metadata, and potentially filenames.

- Store the bundle in an access-controlled UMD location.
- Redact it before attaching it to SysAid or sending it to a vendor.
- Do not treat the inventory as an application or database backup.
- Do not blindly clone broad firewall rules, obsolete software, service accounts, or inherited permissions onto the replacement.
