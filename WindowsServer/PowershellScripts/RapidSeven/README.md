# Rapid7 InsightVM — Windows Host Preparation Scripts

These scripts prepare Windows VMs for authenticated vulnerability scanning by DIT's Rapid7 InsightVM platform. Run them **locally on each VM** that will be scanned.

| Script | Purpose |
|---|---|
| `New-Rapid7ServiceAccount.ps1` | Creates a local admin service account for Rapid7 to authenticate with |
| `Deploy-Rapid7FirewallRules.ps1` | Opens the DIT scanning subnet through Windows Firewall |

## Prerequisites

- **PowerShell 5.1+** (built into Windows Server 2016+)
- **Run as Administrator** — both scripts require elevation
- No additional modules needed — everything uses built-in cmdlets

## Recommended Order

1. **Service Account** first — creates the account, adds it to Administrators, sets the UAC registry key
2. **Firewall Rules** second — opens inbound access for the scanning subnet
3. **Verify** WMI connectivity and hand credentials to DIT

---

## New-Rapid7ServiceAccount.ps1

Creates a local user account (`LIBR-InsightVM` by default), adds it to the local Administrators group, and sets the `LocalAccountTokenFilterPolicy` registry key so remote admin authentication works through UAC.

### Usage

```powershell
# Create the account (prompts for password with confirmation)
.\New-Rapid7ServiceAccount.ps1

# Preview what would happen without making changes
.\New-Rapid7ServiceAccount.ps1 -WhatIf

# Use a custom account name
.\New-Rapid7ServiceAccount.ps1 -AccountName "rapid7-svc"

# Remove the account and undo all changes
.\New-Rapid7ServiceAccount.ps1 -Remove
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `-AccountName` | `LIBR-InsightVM` | Local account name (alphanumeric, hyphens, underscores) |
| `-DisplayName` | `Rapid7 InsightVM Scanner - Library IT` | Full name shown in local user management |
| `-Remove` | — | Removes the account, Administrators membership, and reverts the registry key |
| `-WhatIf` | — | Dry run — shows actions without applying |

### What It Does

1. Validates the script is running elevated
2. Prompts for a password (with confirmation)
3. Creates the local account with `PasswordNeverExpires` and `AccountNeverExpires`
4. Adds the account to the local **Administrators** group
5. Sets `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\LocalAccountTokenFilterPolicy` to `1` — this allows remote admin tools (WMI, SMB) to use the account without UAC stripping the admin token
6. Prints a verification summary and next steps

### Security Notes

- The `LocalAccountTokenFilterPolicy = 1` setting applies to **all** local admin accounts on the machine, not just this one. It allows any local admin to authenticate remotely with full privileges. This is required by Rapid7 for authenticated scanning.
- `-Remove` reverts this key to `0`.

---

## Deploy-Rapid7FirewallRules.ps1

Creates inbound Windows Firewall rules allowing the DIT Rapid7 scanning subnet (`128.8.236.64/27`) full TCP and UDP access.

### Scanning Subnet

| Detail | Value |
|---|---|
| Network | `128.8.236.64/27` |
| Usable Range | `128.8.236.65` – `128.8.236.94` (30 hosts) |
| Netmask | `255.255.255.224` |

### Usage

```powershell
# Run locally on this host
.\Deploy-Rapid7FirewallRules.ps1

# Preview changes
.\Deploy-Rapid7FirewallRules.ps1 -WhatIf

# Deploy to remote hosts (requires WinRM)
.\Deploy-Rapid7FirewallRules.ps1 -ComputerName "LIBWS001", "LIBWS002"

# Remove the firewall rules
.\Deploy-Rapid7FirewallRules.ps1 -Remove
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `-ComputerName` | Local machine | Target computer(s). Accepts pipeline input. |
| `-Remove` | — | Removes the Rapid7 firewall rules |
| `-WhatIf` | — | Dry run |

### What It Does

1. Creates two inbound firewall rules (Domain profile only):
   - **All TCP** from `128.8.236.64/27`
   - **All UDP** from `128.8.236.64/27`
2. Rules are prefixed `DIT-Rapid7-InsightVM` and grouped under `DIT Security Scanning`
3. If rules already exist, they are updated rather than duplicated
4. Prints a results summary table and verifies the rules are active

### Key Ports Used by Rapid7

| Port | Protocol | Purpose |
|---|---|---|
| 135 | TCP | RPC/DCOM — WMI initial connection |
| 139 | TCP | NetBIOS Session |
| 445 | TCP | SMB/CIFS (preferred) |
| 49152–65535 | TCP | WMI dynamic high ports |

The rules open **all** ports from the scanning subnet rather than individual ports, since Rapid7 scans can probe any port for vulnerabilities.

---

## Post-Setup Verification

After running both scripts, verify the account can authenticate remotely:

```powershell
# Test WMI access (run from another machine, or locally)
Get-WmiObject -Class Win32_OperatingSystem -Credential (Get-Credential LIBR-InsightVM)

# Confirm firewall rules are active
Get-NetFirewallRule -DisplayName "DIT-Rapid7*" | Select-Object DisplayName, Enabled, Direction
```

Then provide the account credentials to the DIT security team via a **secure channel** (password manager or encrypted transfer — not email).

---

## Removal / Cleanup

```powershell
# Remove the service account and revert registry
.\New-Rapid7ServiceAccount.ps1 -Remove

# Remove the firewall rules
.\Deploy-Rapid7FirewallRules.ps1 -Remove
```

## Reference

- [Rapid7 InsightVM — Windows Authentication Best Practices](https://docs.rapid7.com/insightvm/authentication-on-windows-best-practices/)
