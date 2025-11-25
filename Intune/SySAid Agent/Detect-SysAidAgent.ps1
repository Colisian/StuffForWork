<#
.SYNOPSIS
  Detection script for SysAid Agent deployment via Intune.

.DESCRIPTION
  Checks if the SysAid Agent service is installed, running, and set to Automatic startup.
  Returns exit code 0 if the agent is properly configured (Intune interprets this as "detected/compliant").
  Returns exit code 1 if the agent is not installed or not configured correctly (Intune will trigger remediation).

.NOTES
  This script should be used as the "Detection script" in Intune Win32 app deployment.
  Intune runs this in SYSTEM context to determine if the application is installed.
#>

$ErrorActionPreference = 'SilentlyContinue'

# Check for SysAid Agent service
$serviceName = "SysAidAgent"
$service = Get-Service -Name $serviceName

if ($null -eq $service) {
    Write-Output "SysAid Agent service not found"
    exit 1
}

if ($service.Status -ne 'Running') {
    Write-Output "SysAid Agent service is not running (Status: $($service.Status))"
    exit 1
}

if ($service.StartType -ne 'Automatic') {
    Write-Output "SysAid Agent service is not set to Automatic (StartType: $($service.StartType))"
    exit 1
}

# All checks passed
Write-Output "SysAid Agent is installed, running, and configured correctly"
exit 0
