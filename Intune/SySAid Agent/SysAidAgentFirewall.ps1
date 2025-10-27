<#
    SysAid Agent Post-Install Script
    Ensures required services are running and firewall rules are configured
#>

Write-Host "Starting SysAid Agent post-install configuration..." -ForegroundColor Cyan

# --- Ensure required services are running ---
$services = @("SysAidAgent", "LanmanServer", "RpcSs", "RemoteRegistry")

foreach ($svc in $services) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($null -ne $service) {
        if ($service.Status -ne 'Running') {
            Write-Host "Starting service: $svc"
            Start-Service -Name $svc -ErrorAction SilentlyContinue
        }
        Set-Service -Name $svc -StartupType Automatic
    } else {
        Write-Host "Service $svc not found." -ForegroundColor Yellow
    }
}

# --- Ensure firewall rules exist ---
$ruleName = "SysAid Agent Port 8193"
if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating inbound firewall rule for SysAid Agent (TCP 8193)..."
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort 8193 -Action Allow
} else {
    Write-Host "Firewall rule already exists for SysAid Agent."
}

# Optional: temporary deployment ports
$deploymentPorts = @(139,445,137,138)
foreach ($port in $deploymentPorts) {
    $tempRule = "SysAid Agent Deploy Port $port"
    if (-not (Get-NetFirewallRule -DisplayName $tempRule -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $tempRule -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow
    }
}

Write-Host "SysAid Agent post-install configuration completed successfully." -ForegroundColor Green
