<#
.SYNOPSIS
    Installs the GIS Lab Check-In Helper scheduled task.

.DESCRIPTION
    Creates a scheduled task that launches a Survey123 check-in form in Edge kiosk mode
    at user logon. Requires administrator privileges.

.NOTES
    Author: GIS Lab
    Version: 1.1

.INTUNE DEPLOYMENT
    Packaging:
        1. Place all 3 scripts in a folder (Install, Launcher, Uninstall)
        2. Use Microsoft Win32 Content Prep Tool:
           IntuneWinAppUtil.exe -c <source_folder> -s Install-GISLabForm.ps1 -o <output_folder>

    Intune App Configuration:
        Install command:    powershell.exe -ExecutionPolicy Bypass -File Install-GISLabForm.ps1
        Uninstall command:  powershell.exe -ExecutionPolicy Bypass -File Uninstall-GISLabForm.ps1
        Install behavior:   System
        Device restart:     No action

    Detection Rules (File-based):
        Path:               C:\ProgramData\GISLab\FormBlocker
        File:               .installed
        Detection method:   File or folder exists

    Requirements:
        OS:                 Windows 10 1903+ / Windows 11
        Architecture:       Both 32-bit and 64-bit

    Return Codes:
        0 = Success
        1 = Failed (admin check, file copy, or task creation)
#>

$BaseDir  = "C:\ProgramData\GISLab\FormBlocker"
$Launcher = "Launcher-GISLabForm.ps1"
$TaskName = "GIS Lab Check-In Helper"
$ScriptPath = Join-Path $BaseDir $Launcher

# Check for admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script requires administrator privileges." -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

# Create directory and copy launcher
try {
    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
    Copy-Item -Path (Join-Path $PSScriptRoot $Launcher) -Destination $ScriptPath -Force
    Write-Host "Copied launcher script to $ScriptPath"
} catch {
    Write-Host "ERROR: Failed to copy files - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# XML definition for a per-user Logon task
$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>GISLab</Author>
    <Description>Launches Survey123 kiosk and dialog at user logon</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT5S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <GroupId>S-1-5-32-545</GroupId> <!-- Users -->
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT1H</ExecutionTimeLimit>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>3</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$ScriptPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$xmlFile = Join-Path $BaseDir "GISLabFormBlocker.task.xml"
$taskXml | Out-File -FilePath $xmlFile -Encoding Unicode -Force

# Register the scheduled task
Write-Host "Registering scheduled task..."
$result = schtasks.exe /Create /TN "$TaskName" /XML "$xmlFile" /F 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to register scheduled task" -ForegroundColor Red
    Write-Host $result -ForegroundColor Red
    exit 1
}

"installed" | Out-File -FilePath (Join-Path $BaseDir ".installed") -Force

Write-Host ""
Write-Host "GIS Lab Check-In Helper installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  - Task Name: $TaskName"
Write-Host "  - Script Path: $ScriptPath"
Write-Host "  - Trigger: 5 second delay after user logon"
Write-Host "  - Retry: Up to 3 times on failure"
Write-Host ""
Write-Host "The form will appear at next user logon." -ForegroundColor Yellow
