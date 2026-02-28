# CLAUDE.md — Oji | Lead IT Engineer, University of Maryland Libraries

## Identity & Environment

- **Role**: Lead IT Engineer — hybrid enterprise (Windows Server, macOS/Jamf, Linux, AWS)
- **Domain**: `AD.UMD.EDU`
- **Primary languages**: PowerShell 7.4+, Bash. Learning: Python, Rust, TypeScript, Terraform, Ansible.
- **Dev environment**: WSL2, Docker, VS Code, Kitty terminal, zsh/Powerlevel10k

## Code Conventions

### PowerShell

- Approved verbs only (`Get-Verb`). `camelCase` locals, `PascalCase` params.
- Every function: `[CmdletBinding()]`, comment-based help (`.SYNOPSIS`, `.NOTES` with Author/Date/Version).
- State-changing functions: `SupportsShouldProcess` + `$PSCmdlet.ShouldProcess()`.
- `$ErrorActionPreference = 'Stop'` in `begin{}`. Wrap risky ops in `try/catch`.
- Structure: `begin{} / process{} / end{}`.

### Bash

- Shebang + header (description, author, date, version).
- `set -euo pipefail`. Log to `/var/log/<script_name>.log` via `tee`.
- `trap 'echo "Error on line $LINENO"; exit 1' ERR`.
- Define functions first, call `main "$@"` last.

### General

- Never hardcode credentials. Use: SecureString (PS), AWS Secrets Manager, Azure Key Vault, macOS Keychain.
- All scripts get inline comments on non-obvious logic and a header block.
- Provide verification/test commands alongside any solution.

## Infrastructure Reference

| System | Details |
|---|---|
| AD Domain | `AD.UMD.EDU` |
| Pharos Print Server | `LIBRPS406DV.AD.UMD.EDU` |
| Common OU | `OU=LIBR,DC=ad,DC=umd,DC=edu` |
| Campus IP Range | `128.8.x.x` |
| Printer Naming | `LIB-[LOCATION]-[TYPE]` (e.g., `LIB-McKMobileBW`) |
| macOS Mgmt | Jamf Pro |
| Windows Mgmt | Microsoft Intune / Entra ID |
| Code Signing Team ID | `PBMCJ9DTL3` |
| Apple ID (notarization) | `cmcleod1@umd.edu` |
| Keychain Profile | `UMD-Notary` |
| Package Identifier Prefix | `edu.umd.libraries.*` |
| GitHub | `@Colisian` |

## macOS Packaging Workflow

Order: `pkgbuild` → `productsign` → `xcrun notarytool submit --wait` → upload to Jamf.
Scripts must be named exactly `preinstall` / `postinstall` (no extension), `chmod +x`.
Printer setup uses `lpadmin` with `lpd://PHAROS_SERVER/PRINTER_IP` and Canon UFR II PPDs.

## Common Deployment Patterns

- **Network drives (Intune)**: `net use` with `/persistent:yes`, remove existing first with `/delete /y`.
- **Registry (Intune)**: `Test-Path` → `New-Item -Force` → `Set-ItemProperty -Force`.
- **File copy**: Validate source exists, create destination dir, `Copy-Item -Force`, exit 1 on failure.
- **EC2 domain join**: Secrets Manager → `ConvertTo-SecureString` → `Add-Computer` to `OU=EC2,OU=Servers,OU=LIBR,...`.

## Behavioral Rules

1. **Diagnose first** — start with quick checks before deep troubleshooting.
2. **Multiple paths** — offer alternatives with pros/cons when there's a real choice.
3. **Security callouts** — flag implications and mitigations proactively.
4. **Beginner framing** for Terraform, Ansible, and AWS topics — relate to existing PS/Bash knowledge.
5. **Output as files** — create downloadable/copy-paste-ready scripts, not inline-only.
6. **Platform differences** — note Windows vs macOS vs Linux when behavior diverges.

## Current Projects

- MCP plugin development for PowerShell in Claude Code
- Terraform: S3 + CloudFront static site hosting
- JAMF Skills for Claude Code
- Equipment database / asset lifecycle management