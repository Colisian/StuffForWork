# Claude Code Configuration for Oji - Lead IT Engineer

## Role & Environment Context

I am a Lead IT Engineer at the University of Maryland Libraries managing a hybrid enterprise environment with the following infrastructure:

### Primary Environment
- **Operating Systems**: Windows Server 2019+, macOS (managed via Jamf Pro), Ubuntu/RHEL 8+
- **Management Platforms**:
  - Microsoft Intune (Windows devices)
  - Jamf Pro (macOS devices)
  - Active Directory (AD.UMD.EDU domain)
  - Azure AD/Entra ID
- **Development Environment**: WSL2, Docker, VS Code, PowerShell 7.4+
- **Cloud Services**: AWS EC2, S3, CloudFront
- **Specialized Systems**: Pharos Uniprint print management, Canon printer infrastructure

### Technical Skills & Focus
- **Primary Languages**: PowerShell, Bash
- **Learning**: Python, Rust, TypeScript, Terraform, Ansible
- **Specializations**:
  - Enterprise automation and deployment
  - macOS package building (pkgbuild, productbuild, Jamf Composer)
  - Print server management (Pharos, Canon UFR II drivers)
  - Infrastructure-as-code (beginning Terraform)
  - Configuration management (beginning Ansible)

---

## Code Standards & Preferences

### PowerShell Standards
```powershell
# Function naming: Use approved verbs (Get-Verb)
# Variables: camelCase for local, PascalCase for parameters
# Always include comment-based help
# Use [CmdletBinding()] for advanced functions
# Include SupportsShouldProcess for state-changing operations

<#
.SYNOPSIS
    Brief description
.DESCRIPTION
    Detailed description
.PARAMETER ParameterName
    Parameter description
.EXAMPLE
    Example usage
.NOTES
    Author: Oji
    Date: $(Get-Date -Format 'yyyy-MM-dd')
    Version: 1.0
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ComputerName
)

begin {
    $ErrorActionPreference = 'Stop'
    Write-Verbose "Starting $($MyInvocation.MyCommand.Name)"
}

process {
    try {
        if ($PSCmdlet.ShouldProcess($ComputerName, "Perform operation")) {
            # Main logic
        }
    }
    catch {
        Write-Error "Failed: $_"
    }
}

end {
    Write-Verbose "Completed"
}
```

### Bash/Shell Standards
```bash
#!/bin/bash
# Script description
# Author: Oji
# Date: $(date +%Y-%m-%d)
# Version: 1.0

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Catch errors in pipelines

# Logging
LOG_FILE="/var/log/script_name.log"
exec &> >(tee -a "$LOG_FILE")

echo "Started: $(date)"

# Functions first
function main() {
    # Main logic
}

# Error handling
trap 'echo "Error on line $LINENO"; exit 1' ERR

# Execute
main "$@"
```

---

## Common Project Patterns

### 1. macOS Printer Deployment Packages

**Project Structure:**
```
PrinterPackage/
├── payload/
│   └── Library/Printers/PPDs/Contents/Resources/
│       └── CNPZUIRAC5030ZU.ppd.gz
├── scripts/
│   ├── preinstall    # Install Canon drivers
│   └── postinstall   # Configure printers
└── resources/
    └── UFRII_LT_LIPS_LX_Installer.pkg
```

**Key Commands:**
```bash
# Build component package
pkgbuild --root ./payload \
         --scripts ./scripts \
         --identifier edu.umd.libraries.printers \
         --version 1.0 \
         --install-location / \
         output.pkg

# Sign package
productsign --sign "Developer ID Installer: University of Maryland College Park (PBMCJ9DTL3)" \
            input.pkg output-signed.pkg

# Notarize
xcrun notarytool submit package.pkg \
      --keychain-profile "UMD-Notary" \
      --wait
```

**Printer Installation Pattern (Pharos + Canon):**
```bash
# Standard printer setup via lpadmin
PRINTER_NAME="LIB-LOCATION-PRINTER"
PRINTER_IP="128.8.xxx.xxx"
PPD_PATH="/Library/Printers/PPDs/Contents/Resources/Canon iR-ADV C5560 UFR II.gz"
PHAROS_SERVER="LIBRPS406DV.AD.UMD.EDU"

/usr/sbin/lpadmin -p "$PRINTER_NAME" \
    -E \
    -v "lpd://$PHAROS_SERVER/$PRINTER_IP" \
    -P "$PPD_PATH" \
    -D "Location Description" \
    -L "Physical Location" \
    -o printer-is-shared=false
```

### 2. PowerShell Intune Deployment Scripts

**Network Drive Mapping:**
```powershell
# Isilon share mapping with error handling
$driveShares = @{
    "1" = @{Name = "Shared Documents"; Path = "\\isilon-server\shared-docs"; DriveLetter = "S"}
}

# Remove existing mapping
if (Test-Path "$($DriveLetter):") {
    net use "$($DriveLetter):" /delete /y | Out-Null
}

# Map drive persistently
net use "$($DriveLetter):" "$Path" /persistent:yes
```

**Registry Configuration:**
```powershell
# Standard registry update pattern
$RegistryPath = "HKLM:\SOFTWARE\..."
$ValueName = "SettingName"
$ValueData = "SettingValue"

if (-not (Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
}

Set-ItemProperty -Path $RegistryPath -Name $ValueName -Value $ValueData -Type String -Force
```

### 3. AWS EC2 Domain Join Automation

**PowerShell User Data Pattern:**
```powershell
# Retrieve credentials from Secrets Manager
$SecretName = "domain-join-credentials"
$Secret = Get-SECSecretValue -SecretId $SecretName | ConvertFrom-Json

# Join domain
$Password = ConvertTo-SecureString $Secret.Password -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential($Secret.Username, $Password)

Add-Computer -DomainName "AD.UMD.EDU" `
             -OUPath "OU=EC2,OU=Servers,OU=LIBR,DC=ad,DC=umd,DC=edu" `
             -Credential $Credential `
             -Restart -Force
```

### 4. File Deployment Scripts

**Standard Pattern:**
```powershell
$destinationPath = "C:\Program Files (x86)\App"
$sourceFolder = Join-Path -Path $PSScriptRoot -ChildPath "Files"
$filename = "config.dbc"
$sourceFile = Join-Path -Path $sourceFolder -ChildPath $filename

# Create destination if needed
if (-not (Test-Path -Path $destinationPath)) {
    New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
}

# Verify source exists
if (-not (Test-Path -Path $sourceFile)) {
    Write-Output "Source file does not exist. Exiting..."
    exit 1
}

# Copy with error handling
try {
    Copy-Item -Path $sourceFile -Destination $destinationPath -Force
    Write-Output "File copied successfully"
} catch {
    Write-Output "Failed to copy file: $_"
    exit 1
}
```

---

## Tool-Specific Patterns

### Jamf Pro Package Building

**Workflow:**
1. Create package structure with payload and scripts
2. Use `pkgbuild` for component packages
3. Use `productbuild` for distribution packages
4. Sign with Developer ID Installer certificate
5. Notarize with Apple
6. Upload to Jamf Pro

**Critical Script Naming:**
- `preinstall` (no extension) - runs before payload installation
- `postinstall` (no extension) - runs after payload installation
- Scripts must be executable: `chmod +x scriptname`

### Ansible (Learning Phase)

**Lab Environment Setup:**
```bash
# WSL2 + Docker for Windows management
docker run -d --name ansible-control \
    -v $(pwd):/ansible \
    ubuntu:latest

# Install Ansible
apt-get update && apt-get install -y ansible
```

### Terraform (Learning Phase)

**Current Projects:**
- S3 + CloudFront static site hosting
- Infrastructure-as-code for AWS resources
- State management with remote backend

---

## Security Standards

### Credential Management
- **Never** hardcode passwords in scripts
- Use SecureString in PowerShell
- Use AWS Secrets Manager for cloud credentials
- Use Azure Key Vault for enterprise secrets
- Keychain for macOS credential storage

### Code Signing
- All packages must be signed with University of Maryland Developer ID
- Team ID: `PBMCJ9DTL3`
- Apple ID: `cmcleod1@umd.edu`
- Notarization required for all macOS packages

### Privileged Operations
- Always check for admin/root privileges
- Use proper error handling for privileged commands
- Log all privileged operations
- Include `-WhatIf` support for testing

---

## Documentation Preferences

### Output Format
- Use Markdown with clear headings
- Include code blocks with syntax highlighting
- Provide both detailed explanations and TL;DR summaries
- Include "Plain Language Summary" sections for complex topics
- Format in copy-paste ready format for VS Code

### Code Comments
- Include inline comments for complex logic
- Add header blocks with purpose, author, date, version
- Document assumptions and dependencies
- Note any UMD-specific configurations

### Technical Documentation
- Provide step-by-step guides with numbered instructions
- Include diagnostic commands for troubleshooting
- Add tables for comparing approaches (pros/cons)
- Include verification steps after operations

---

## Current Learning Focus

### Infrastructure as Code
- Terraform basics and AWS provider usage
- State file management
- Module creation for reusable components

### Configuration Management
- Ansible playbook development
- Windows management via WinRM
- Inventory management
- Role-based configuration

### Scripting Evolution
- PowerShell → Python for cross-platform support
- Bash → Advanced shell scripting patterns
- TypeScript for API integrations
- Rust for performance-critical tools

---

## Common Task Shortcuts

### Quick Package Build (macOS)
```bash
# Build, sign, and notarize in one command
pkgbuild --root ./payload --scripts ./scripts \
         --identifier edu.umd.libraries.app --version 1.0 \
         --install-location / app.pkg && \
productsign --sign "Developer ID Installer: University of Maryland College Park (PBMCJ9DTL3)" \
            app.pkg app-signed.pkg && \
xcrun notarytool submit app-signed.pkg --keychain-profile "UMD-Notary" --wait
```

### Quick PowerShell Script Template
```powershell
# Generate with proper structure
$ScriptName = "New-Script"
@"
<#
.SYNOPSIS
    Brief description
.DESCRIPTION
    Detailed description
.EXAMPLE
    .\$ScriptName.ps1
.NOTES
    Author: Oji
    Date: $(Get-Date -Format 'yyyy-MM-dd')
#>
[CmdletBinding()]
param()

begin {
    Write-Verbose "Starting $ScriptName"
}

process {
    # Main logic
}

end {
    Write-Verbose "Completed"
}
"@ | Out-File "$ScriptName.ps1"
```

### Quick Connectivity Test (Pharos Servers)
```bash
# Test all required ports
for port in 515 139 445 28203; do
    printf "Port %-6s: " "$port"
    if nc -z -w 2 LIBRPS406DV.umd.edu $port 2>/dev/null; then
        echo "✓ OPEN"
    else
        echo "✗ CLOSED"
    fi
done
```

---

## Project-Specific Notes

### University of Maryland Libraries Infrastructure

**Domain:** AD.UMD.EDU
**Pharos Print Server:** LIBRPS406DV.AD.UMD.EDU
**Common OU Paths:** OU=LIBR,DC=ad,DC=umd,DC=edu

**Printer Naming Convention:** `LIB-[LOCATION]-[TYPE]`
Examples: LIB-McKMobileBW, LIB-ArchMobileColor

**IP Ranges:** 128.8.x.x (campus network)

### Common Software Deployments
- Canon UFR II Universal Print Drivers
- Pharos Popup (print authentication)
- ABBYY FineReader Server
- Atlas Systems (Aeon, ILLiad)
- Microsoft Office via Intune

---

## Response Preferences for Claude

### When Providing Solutions
1. **Start with quick diagnostic checks** before deep troubleshooting
2. **Offer multiple solution paths** when possible, noting pros/cons
3. **Highlight security implications** and mitigation steps
4. **Include verification commands** to confirm success
5. **Provide automation opportunities** where applicable

### Code Outputs
- Format as downloadable files when creating scripts
- Include both full solutions and modular components
- Provide testing strategies before production deployment
- Note Windows vs. macOS vs. Linux differences clearly

### Learning New Technologies
- Include short learning roadmap with key concepts
- Provide hands-on examples for practice
- Suggest relevant documentation and resources
- Relate to existing PowerShell/Bash knowledge when possible

---

## Recent Project Examples

### Completed Projects
- macOS printer deployment package with Pharos integration (17 printers)
- PowerShell network drive mapping via Intune
- EC2 domain join automation with Secrets Manager
- Python PATH configuration deployment
- Ansible lab environment in WSL2

### Current Projects
- MCP plugin development for PowerShell in Claude Code
- Terraform static site hosting (S3 + CloudFront)
- JAMF Skills for Claude Code
- Terminal customization and workflow optimization

### Planned Projects
- Equipment database for asset lifecycle management
- Enhanced IT documentation system
- Automated troubleshooting workflows

---

## Version Information

**Last Updated:** 2026-01-16
**Environment:** University of Maryland Libraries
**Primary Systems:** Windows Server, macOS (Jamf), Ubuntu/RHEL, AWS EC2
**Code Repository:** Personal GitHub - @Colisian

---

*This configuration file helps Claude Code provide context-aware assistance for enterprise IT engineering tasks with a focus on automation, deployment, and infrastructure management.*
