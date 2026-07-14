<#
.SYNOPSIS
    Installs the GIS Lab Check-In Helper scheduled task.

.DESCRIPTION
    Copies the launcher script to ProgramData and registers a scheduled task
    that launches the Survey123 check-in form (Edge kiosk + attestation dialog)
    at every user logon. Requires administrator/SYSTEM privileges.

.NOTES
    Author:  GIS Lab
    Date:    2026-07-10
    Version: 2.0
    Log:     C:\ProgramData\GISLab\FormBlocker\install.log

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
[CmdletBinding()]
param()

$BaseDir    = 'C:\ProgramData\GISLab\FormBlocker'
$Launcher   = 'Launcher-GISLabForm.ps1'
$TaskName   = 'GIS Lab Check-In Helper'
$ScriptPath = Join-Path $BaseDir $Launcher
$exitCode   = 0

New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
Start-Transcript -Path (Join-Path $BaseDir 'install.log') -Append | Out-Null

try {
    $ErrorActionPreference = 'Stop'

    # Check for admin privileges (SYSTEM passes this when deployed via Intune)
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw 'This script requires administrator privileges.'
    }

    Copy-Item -Path (Join-Path $PSScriptRoot $Launcher) -Destination $ScriptPath -Force
    Write-Host "Copied launcher script to $ScriptPath"

    # Per-user logon task. LeastPrivilege: the launcher needs no elevation, and
    # HighestAvailable would silently elevate it for any admin who logs on.
    # ExecutionTimeLimit PT0S = no limit; the launcher lives until the user
    # confirms and ends naturally at logoff.
    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>GISLab</Author>
    <Description>Launches Survey123 check-in form and dialog at user logon</Description>
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
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
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

    $xmlFile = Join-Path $BaseDir 'GISLabFormBlocker.task.xml'
    $taskXml | Out-File -FilePath $xmlFile -Encoding Unicode -Force

    Write-Host 'Registering scheduled task...'
    $result = schtasks.exe /Create /TN "$TaskName" /XML "$xmlFile" /F 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to register scheduled task: $result"
    }

    "installed $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath (Join-Path $BaseDir '.installed') -Force

    Write-Host ''
    Write-Host 'GIS Lab Check-In Helper installed successfully!'
    Write-Host "  - Task Name: $TaskName"
    Write-Host "  - Script Path: $ScriptPath"
    Write-Host '  - Trigger: 5 second delay after user logon'
    Write-Host 'The form will appear at next user logon.'
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    $exitCode = 1
}
finally {
    Stop-Transcript | Out-Null
}

exit $exitCode
