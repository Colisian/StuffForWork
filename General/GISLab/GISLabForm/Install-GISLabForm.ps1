<#
.SYNOPSIS
    Installs the GIS Lab Check-In Helper scheduled task.

.DESCRIPTION
    Copies the launcher to a protected ProgramData directory and registers a
    per-user logon task that opens the Survey123 check-in experience.

.NOTES
    Author:  GIS Lab
    Date:    2026-09-06
    Version: 2.1
    Log:     C:\ProgramData\UMDLibraries\GISLabForm\DeploymentLogs\install.log

.INTUNE DEPLOYMENT
    Package all four scripts. For script-driven packaging, use a bundled file
    as the required setup-file placeholder:

        IntuneWinAppUtil.exe -c <source_folder> -s Launcher-GISLabForm.ps1 -o <output_folder>

    Install command:
        powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-GISLabForm.ps1

    Optional ArcGIS Pro launch after check-in:
        Add -LaunchArcGISProAfter to the install command.

    Uninstall command:
        powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-GISLabForm.ps1

    Install behavior: System
    Detection rule:  Use Detection-GISLabForm.ps1 as a custom detection script.
    Return codes:    0 = success; 1 = failure
#>
[CmdletBinding()]
param(
    [switch] $LaunchArcGISProAfter
)

$ErrorActionPreference = 'Stop'
$appVersion = '2.1'
$rootDir = 'C:\ProgramData\UMDLibraries\GISLabForm'
$appDir = Join-Path $rootDir 'App'
$runtimeLogDir = Join-Path $rootDir 'Logs'
$deploymentLogDir = Join-Path $rootDir 'DeploymentLogs'
$launcherName = 'Launcher-GISLabForm.ps1'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$sourceLauncher = Join-Path $scriptDir $launcherName
$launcherPath = Join-Path $appDir $launcherName
$versionPath = Join-Path $appDir 'version.txt'
$taskXmlPath = Join-Path $appDir 'GISLabForm.task.xml'
$taskName = 'GIS Lab Check-In Helper'
$transcriptStarted = $false
$exitCode = 0

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Error 'This script requires administrator or SYSTEM privileges.'
    exit 1
}

try {
    if (-not (Test-Path -LiteralPath $sourceLauncher -PathType Leaf)) {
        throw "Bundled launcher was not found: $sourceLauncher"
    }

    foreach ($directory in @($appDir, $runtimeLogDir, $deploymentLogDir)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    # Protect executable content and deployment logs from standard-user changes.
    foreach ($protectedDir in @($appDir, $deploymentLogDir)) {
        $aclResult = & icacls.exe $protectedDir '/inheritance:r' `
            '/grant:r' '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' `
            '*S-1-5-32-545:(OI)(CI)(RX)' 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to secure $protectedDir`: $aclResult"
        }
    }

    # Runtime logs are informational and must be writable by interactive users.
    $aclResult = & icacls.exe $runtimeLogDir '/inheritance:r' `
        '/grant:r' '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' `
        '*S-1-5-32-545:(OI)(CI)(M)' 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to configure runtime-log permissions: $aclResult"
    }

    Start-Transcript -Path (Join-Path $deploymentLogDir 'install.log') -Append | Out-Null
    $transcriptStarted = $true

    # Remove the marker first so a failed upgrade cannot pass detection.
    Remove-Item -LiteralPath $versionPath -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $sourceLauncher -Destination $launcherPath -Force

    $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $taskArguments = "-NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File &quot;$launcherPath&quot;"
    if ($LaunchArcGISProAfter) {
        $taskArguments += ' -LaunchArcGISProAfter'
    }
    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>UMD Libraries</Author>
    <Description>Launches the GIS Lab Survey123 check-in form at user logon</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><Delay>PT5S</Delay></LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <GroupId>S-1-5-32-545</GroupId>
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
    <RestartOnFailure><Interval>PT1M</Interval><Count>3</Count></RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$powerShellPath</Command>
      <Arguments>$taskArguments</Arguments>
    </Exec>
  </Actions>
</Task>
"@

    $taskXml | Out-File -FilePath $taskXmlPath -Encoding Unicode -Force
    $taskResult = & schtasks.exe /Create /TN $taskName /XML $taskXmlPath /F 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to register scheduled task: $taskResult"
    }

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    $expectedAction = $task.Actions | Where-Object {
        $_.Execute -ieq $powerShellPath -and $_.Arguments -match [regex]::Escape($launcherPath)
    }
    if (-not $expectedAction -or $task.State -eq 'Disabled') {
        throw 'Scheduled-task verification failed.'
    }

    $appVersion | Out-File -FilePath $versionPath -Encoding ascii -Force
    Write-Host "GIS Lab Check-In Helper $appVersion installed successfully."
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    $exitCode = 1
}
finally {
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch {}
    }
}

exit $exitCode
