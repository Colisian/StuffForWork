#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads and silently installs the Rapid7 Insight Agent (InsightVM) from the
    ITFO Nexus repository, then verifies the agent service is running.

.DESCRIPTION
    Wraps the standard Rapid7 msiexec install command with pre-flight diagnostics,
    a resilient download, exit-code handling, and post-install verification.
    Designed for Windows Server / Windows VMs running on AWS EC2.

    Equivalent manual command:
        msiexec /i agentInstaller-x86_64.msi /l*v insight_agent_install_log.log /quiet `
            CUSTOMTOKEN=us:c45babf3-1665-470a-95b6-ced3099846e8 CUSTOMATTRIBUTES="LIBR-DC"

.PARAMETER InstallerUrl
    Full URL to the agentInstaller-x86_64.msi in the Nexus repo.

.PARAMETER CustomToken
    Rapid7 organization install token (region-prefixed, e.g. us:<guid>).
    SECURITY: prefer passing this at runtime or pulling from AWS Secrets Manager /
    SSM Parameter Store rather than committing it to source control.

.PARAMETER CustomAttributes
    Custom attribute tag(s) applied to the agent in the Insight platform.

.PARAMETER WorkDir
    Local working directory for the downloaded MSI and install log.

.PARAMETER Force
    Reinstall even if an existing Insight Agent service is detected.

.EXAMPLE
    .\Install-Rapid7InsightAgent.ps1

.EXAMPLE
    .\Install-Rapid7InsightAgent.ps1 -CustomToken 'us:xxxxxxxx-...' -CustomAttributes 'LIBR-DC' -Verbose

.NOTES
    Author : ITFO / UMD Libraries
    Service: ir_agent  (default Windows service name for the Rapid7 Insight Agent)
    msiexec exit codes treated as success: 0 (OK), 3010 (OK, reboot required)
#>

[CmdletBinding()]
param(
    [string]$InstallerUrl     = 'https://maven.lib.umd.edu/nexus/repository/itfo-dropbox/installers/rapid7/insightvm/agentInstaller-x86_64.msi',
    [string]$CustomToken      = 'us:c45babf3-1665-470a-95b6-ced3099846e8',
    [string]$CustomAttributes = 'LIBR-DC',
    [string]$WorkDir          = (Join-Path $env:ProgramData 'ITFO\rapid7-install'),
    [switch]$Force
)

# --- Setup -----------------
$ErrorActionPreference = 'Stop'
$ServiceName = 'ir_agent'
$MsiName     = 'agentInstaller-x86_64.msi'
$MsiPath     = Join-Path $WorkDir $MsiName
$LogPath     = Join-Path $WorkDir 'insight_agent_install_log.log'

function Write-Step { param([string]$Message) Write-Host "[*] $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "[x] $Message" -ForegroundColor Red }

Write-Step "Rapid7 Insight Agent install starting on $env:COMPUTERNAME"

# --- 1. Pre-flight diagnostics ----
Write-Step 'Running pre-flight checks...'

# 1a. Already installed?
$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing -and -not $Force) {
    Write-Warn "Service '$ServiceName' already exists (Status: $($existing.Status))."
    Write-Warn "Agent appears to be installed. Re-run with -Force to reinstall. Exiting."
    return
}

# 1b. Enforce TLS 1.2 for the download (older Server builds default to TLS 1.0)
[Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# 1c. Working directory
if (-not (Test-Path $WorkDir)) {
    New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
}

# 1d. Reachability check against the Nexus host
$nexusHost = ([Uri]$InstallerUrl).Host
Write-Step "Testing connectivity to $nexusHost (443)..."
$conn = Test-NetConnection -ComputerName $nexusHost -Port 443 -WarningAction SilentlyContinue
if (-not $conn.TcpTestSucceeded) {
    Write-Err "Cannot reach $nexusHost on 443. Check VPC routing / Security Group egress / DNS."
    throw "Connectivity pre-check failed."
}
Write-Ok "Connectivity to $nexusHost confirmed."

# --- 2. Download the MSI ------------------------------------------------------
Write-Step "Downloading installer from Nexus..."
try {
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $MsiPath -UseBasicParsing
}
catch {
    Write-Err "Invoke-WebRequest failed: $($_.Exception.Message)"
    Write-Step "Retrying with BITS..."
    Start-BitsTransfer -Source $InstallerUrl -Destination $MsiPath
}

if (-not (Test-Path $MsiPath) -or ((Get-Item $MsiPath).Length -lt 1KB)) {
    throw "Downloaded file missing or too small — download likely failed."
}
$sizeMB = [math]::Round((Get-Item $MsiPath).Length / 1MB, 2)
Write-Ok "Downloaded $MsiName ($sizeMB MB) to $MsiPath"

# --- 3. Silent install --------------------------------------------------------
Write-Step 'Running silent install via msiexec...'
$msiArgs = @(
    '/i', "`"$MsiPath`"",
    '/l*v', "`"$LogPath`"",
    '/quiet',
    "CUSTOMTOKEN=$CustomToken",
    "CUSTOMATTRIBUTES=`"$CustomAttributes`""
)

$proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
$code = $proc.ExitCode

switch ($code) {
    0     { Write-Ok 'msiexec completed successfully (exit 0).' }
    3010  { Write-Warn 'Install succeeded but a REBOOT is required (exit 3010).' }
    1603  { Write-Err 'Fatal error during installation (exit 1603). Review the log.'; throw "msiexec exit $code" }
    1618  { Write-Err 'Another install is already in progress (exit 1618). Retry later.'; throw "msiexec exit $code" }
    1638  { Write-Warn 'Another version is already installed (exit 1638).' }
    default { Write-Err "msiexec returned unexpected exit code $code. Review the log."; throw "msiexec exit $code" }
}

# --- 4. Post-install verification --------------------------------------------
Write-Step 'Verifying agent service...'
Start-Sleep -Seconds 5
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -ne 'Running') {
        Write-Warn "Service '$ServiceName' found but not running. Attempting start..."
        Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
        $svc.Refresh()
    }
    Write-Ok "Service '$ServiceName' status: $($svc.Status)"
}
else {
    Write-Warn "Service '$ServiceName' not detected yet. It may take a few minutes to register, or the service name differs in your build. Check the log: $LogPath"
}

Write-Step "Done. Full MSI log: $LogPath"
Write-Ok  "The agent should appear in the Insight platform under tag '$CustomAttributes' shortly."