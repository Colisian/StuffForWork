$BaseDir  = "C:\ProgramData\GISLab\FormBlocker"
$Launcher = "Launcher-GISLab.ps1"
$TaskName = "GIS Lab Check-In Helper"
$ScriptPath = Join-Path $BaseDir $Launcher

New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot $Launcher) -Destination $ScriptPath -Force

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
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -File "$ScriptPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$xmlFile = Join-Path $BaseDir "GISLabFormBlocker.task.xml"
$taskXml | Out-File -FilePath $xmlFile -Encoding Unicode -Force

# Register the scheduled task
schtasks.exe /Create /TN "$TaskName" /XML "$xmlFile" /F | Out-Null

"installed" | Out-File -FilePath (Join-Path $BaseDir ".installed") -Force
Write-Host "GIS Lab Check-In Helper installed."
