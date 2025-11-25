<#
.SYNOPSIS
  Post-install configuration for SysAid Agent (Windows clients) — your UMD Libraries scenario.

.DESCRIPTION
  Runs in SYSTEM context. Ensures the SysAidAgent service is present, set to automatic and running.
  Optionally creates an inbound firewall rule for port 8193 (TCP) *only if you plan to allow remote control into the client*.
  Returns 0 on success, non-zero on failure for Intune detection.

.NOTES
  Based on SysAid documentation:
    - After deployment, only port 8193 must be kept open for full functionality. :contentReference[oaicite:4]{index=4}
    - Remote control via RCG uses outbound port 443; no inbound port required on client. :contentReference[oaicite:5]{index=5}
#>

[CmdletBinding()]
param (
    [switch]$EnableInbound8193  # Set this flag if you will allow inbound port 8193 remote control.
)

$ErrorActionPreference = 'Stop'
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\SysAid-Configure.log"

function Write-Log {
    param(
        [string]$m,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] $m"

    # Write to log file
    try {
        $logDir = Split-Path -Path $LogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logMessage | Out-File -FilePath $LogPath -Append -Encoding UTF8
    } catch {
        # Silently continue if logging fails
    }

    # Write to console with color
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        default { "Cyan" }
    }
    Write-Host "[$Level] $m" -ForegroundColor $color
}

function Write-Info { param($m) Write-Log -m $m -Level "INFO" }
function Write-Warn { param($m) Write-Log -m $m -Level "WARN" }
function Write-Err  { param($m) Write-Log -m $m -Level "ERROR" }

try {
    Write-Info "Starting SysAid Agent post-install configuration..."

    # Service check
    $svcName = "SysAidAgent"
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        Write-Warn "Service '$svcName' not found. Is the agent installed?"
    } else {
        Write-Info "Service '$svcName' found. Status: $($svc.Status)"
        if ($svc.Status -ne 'Running') {
            Write-Info "Attempting to start service '$svcName'..."
            Start-Service -Name $svcName -ErrorAction Stop
            Write-Info "Service '$svcName' started."
        }
        Set-Service -Name $svcName -StartupType Automatic
        Write-Info "Service '$svcName' startup type set to Automatic."
    }

    if ($EnableInbound8193) {
        # Firewall rule for inbound port 8193
        $port     = 8193
        $ruleName = "SysAid Agent Inbound 8193 (TCP)"
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($null -eq $existing) {
            Write-Info "Creating inbound firewall rule for port $port (TCP) – rule name '$ruleName'..."
            New-NetFirewallRule -DisplayName $ruleName `
                                -Direction Inbound `
                                -Action Allow `
                                -Enabled True `
                                -Protocol TCP `
                                -LocalPort $port `
                                -Profile Any `
                                -Program Any `
                                -Description "Inbound rule for SysAid Agent remote control – adjust scope if needed"
            Write-Info "Firewall rule '$ruleName' created."
            # OPTIONAL: restrict remote addresses – uncomment and set your management subnets
            # Set-NetFirewallRule -DisplayName $ruleName -RemoteAddress "10.0.0.0/8","192.168.0.0/16"
        } else {
            Write-Info "Firewall rule '$ruleName' already exists."
        }
    } else {
        Write-Info "Inbound port 8193 rule not enabled (EnableInbound8193 = $false)."
    }

    Write-Info "SysAid Agent post-install configuration completed successfully."
    exit 0
}
catch {
    Write-Err "Post-install configuration failed: $($_.Exception.Message)"
    exit 1
}
