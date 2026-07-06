# CLAUDE.md — Oji | Lead IT Engineer, University of Maryland Libraries

## Identity & Environment

- **Role**: Lead IT Engineer, ITFO / Digital Services & Technologies — hybrid enterprise (Windows/Intune, macOS/Jamf Pro, Linux, AWS EC2)
- **Domain**: `AD.UMD.EDU`
- **Primary languages**: PowerShell 7.4+, Bash. Learning: Python, Terraform, Ansible, Kubernetes.
- **Cert path**: AWS CloudOps Associate → SAA-C03 → DOP-C02; Terraform Associate + CKA in parallel.
- **Dev environment**: WSL2, Docker, VS Code, Kitty terminal, zsh/Powerlevel10k. Notes live in Obsidian (`Colisian/obsidian-vault`, Git-synced).

## Code Conventions

### PowerShell

- Approved verbs only (`Get-Verb`). `camelCase` locals, `PascalCase` params.
- Every function: `[CmdletBinding()]`, comment-based help (`.SYNOPSIS`, `.NOTES` with Author/Date/Version).
- State-changing functions: `SupportsShouldProcess` + `$PSCmdlet.ShouldProcess()`.
- `$ErrorActionPreference = 'Stop'` in `begin{}`. Wrap risky ops in `try/catch`.
- Intune scripts must run non-interactively as SYSTEM; log to `C:\ProgramData\<Component>\<script>.log` via `Start-Transcript` or custom logger.

### Bash

- Shebang + header (description, author, date, version). `set -euo pipefail`.
- `trap 'echo "Error on line $LINENO"; exit 1' ERR`. Functions first, `main "$@"` last.
- Jamf scripts: parameters start at `$4`; user-context actions run as console user via `su - "$loggedInUser" -c '...'`.

### General

- Never hardcode credentials. Use: SecureString (PS), AWS Secrets Manager, macOS Keychain, Jamf/Intune parameters.
- Provide verification/test commands alongside any solution.
- Runbooks/docs should be Obsidian-compatible Markdown.

## Infrastructure Reference

| System | Details |
|---|---|
| AD Domain / OU | `AD.UMD.EDU`; LIBR OU: `OU=LIBR,OU=Departments,OU=UMD,DC=ad,DC=umd,DC=edu` |
| IP space | Campus public `128.8.x.x` / `129.2.x.x`; library device ranges `10.176.200.0/24`, `10.177.0.0/24` (Infoblox, DIT-controlled `/16` containers) |
| Print servers | `LIBRPS406DV` (Pharos Uniprint), `LIBRPS403V`; printers `LIB-[LOCATION]-[TYPE]`, Canon UFR II/PPD |
| ILLiad/Aeon server | `LIBRAP013V` — public `129.2.176.37` / private `10.126.5.89` split; **use private IP in connection strings** (DNS split-brain history) |
| Ticketing | SysAid on Tomcat: `ticketing.lib.umd.edu` (prod), `ticketingdev` (dev); InCommon/Sectigo certs — use **Replace**, not Renew; include `USERTrust RSA` intermediate |
| File storage | Isilon NAS (SMB shares); DIT migrating shares to VPN-only access |
| Security stack | CrowdStrike Falcon, Rapid7 InsightVM (EC2 agents via SSM Run Command) |
| macOS signing | Team ID `PBMCJ9DTL3`, Apple ID `cmcleod1@umd.edu`, keychain profile `UMD-Notary`, pkg IDs `edu.umd.libraries.*` |
| GitHub | `@Colisian` |

## Deployment Doctrine

- **Windows: Intune-native only — never GPO.** Entire fleet (including lab PCs) is Intune-managed. Use Win32 apps, Settings Catalog, Remediations, Platform Scripts.
- **Win32 apps**: package with `IntuneWinAppUtil`; PowerShell install/uninstall wrappers, custom detection scripts, meaningful exit codes (0 success, 1 failure, 3010 reboot).
- **Remediations**: detection exits 0 (compliant) / 1 (remediate); keep stdout <2048 chars.
- **Registry**: `Test-Path` → `New-Item -Force` → `Set-ItemProperty -Force`.
- **EC2 domain join**: Secrets Manager → `ConvertTo-SecureString` → `Add-Computer` to `OU=EC2,OU=Servers,OU=LIBR,...`; fleet ops via SSM Run Command.
- **macOS packaging**: `pkgbuild` → `productsign` → `xcrun notarytool submit --wait` → Jamf. Scripts named exactly `preinstall`/`postinstall`, `chmod +x`.
- **Kiosk/signage**: prefer All Users Startup folder for auto-launch apps (AxisTV Engage pattern).

## Behavioral Rules

1. **Diagnose first** — quick checks before deep troubleshooting.
2. **Multiple paths** — offer alternatives with pros/cons when there's a real choice.
3. **Security callouts** — flag implications and mitigations proactively (CrowdStrike/Rapid7 detection impact included).
4. **Beginner framing** for Terraform, Ansible, AWS, Kubernetes — relate to existing PS/Bash knowledge; include short learning roadmaps.
5. **Output as files** — downloadable, copy-paste-ready scripts and Obsidian-ready runbooks, not inline-only.
6. **Platform differences** — note Windows vs macOS vs Linux divergence.
7. **Stakeholder comms** — when asked, produce plain-language versions for non-technical library staff.

## Current Projects

- Infoblox DHCP: awaiting DIT `/24` network objects (`10.176.200.0/24`, `10.177.0.0/24`) before adding fixed-address reservations
- `av.lib.umd.edu` access migration: Intune/Jamf device groups → DIT-provisioned IP range → AWS Security Group rules
- Lab app-usage tracking: Event ID 4688/4689 auditing → harvester CSV at `C:\ProgramData\LabUsage\usage.csv`
- MCP plugin development for PowerShell in Claude Code; Jamf skills for Claude Code
- Terraform: S3 + CloudFront static site; equipment/asset lifecycle database