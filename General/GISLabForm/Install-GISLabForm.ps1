<# 
  Install-GISLabFormBlocker.ps1
  - Copies launcher to C:\ProgramData\GISLab\FormBlocker
  - Creates a per-user logon Scheduled Task to run the launcher
#>

$BaseDir   = "C:\ProgramData\GISLab\FormBlocker"
$Launcher  = "Launcher-GISLabFormBlocker.ps1"
$TaskName  = "GISLab Check-In Form Blocker"
$Log       = Join-Path $BaseDir "Install.log"

New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot $Launcher) -Destination (Join-Path $BaseDir $Launcher) -Force

# Create an XML for a per-user logon task (runs in user context, highest privileges)
$launcherPathEsc = (Join-Path $BaseDir $Launcher).Replace('\','\\')
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>GISLab</Author>
    <Description>Launches Survey123 and desktop blocker at user logon</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <GroupId>S-1-5-32-545</GroupId> <!-- Users group -->
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$launcherPathEsc"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$taskXmlPath = Join-Path $BaseDir "FormBlocker.task.xml"
$xml | Out-File -FilePath $taskXmlPath -Encoding Unicode -Force

# Register task
schtasks.exe /Create /TN "$TaskName" /XML "$taskXmlPath" /F | Out-Null

# Write a detection file
"installed" | Out-File -FilePath (Join-Path $BaseDir ".installed") -Force

Write-Host "Installed."
