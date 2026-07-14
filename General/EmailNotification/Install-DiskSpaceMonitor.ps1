<#
.SYNOPSIS
    Installs the Disk Space Monitor: copies the check script, writes its config, and registers the scheduled task.

.DESCRIPTION
    Intended to run as SYSTEM (Intune Win32 install command) or from an elevated prompt.
    - Copies Invoke-DiskSpaceCheck.ps1 to C:\Program Files\DiskSpaceMonitor
    - Writes config.json to C:\ProgramData\DiskSpaceMonitor
    - Registers a daily scheduled task running as SYSTEM with StartWhenAvailable,
      so a machine that was off at the trigger time still runs the check when it boots.

    Exit codes: 0 = success, 1 = failure.

.PARAMETER EmailTo
    One or more recipient addresses.

.PARAMETER EmailFrom
    Sender address the relay will accept.

.PARAMETER SmtpServer
    SMTP relay hostname. For on-campus use, confirm the DIT internal relay host;
    unauthenticated port 25 is the default pattern.

.PARAMETER SmtpPort
    SMTP port. Default 25 (internal relay). Use 587 with -UseSsl for submission.

.PARAMETER UseSsl
    Use STARTTLS when connecting to the relay.

.PARAMETER CredentialXmlPath
    Optional path to a DPAPI-encrypted PSCredential (Export-Clixml) if the relay
    requires authentication. Must be exported by SYSTEM on this machine — see README.

.PARAMETER ThresholdGB
    Free-space threshold in GB. Default 200.

.PARAMETER DriveLetters
    Drive letters to monitor. Default: C.

.PARAMETER ReAlertHours
    Minimum hours between repeat alerts while the condition persists. Default 24.

.PARAMETER DailyTime
    Time of day for the daily check. Default 3:00 AM.

.EXAMPLE
    PS> .\Install-DiskSpaceMonitor.ps1 -EmailTo cmcleod1@umd.edu -EmailFrom cmcleod1@umd.edu -SmtpServer smtp.umd.edu

.NOTES
    Author:  Colisian (cmcleod1@umd.edu)
    Date:    2026-07-14
    Version: 2.0
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string[]]$EmailTo,
    [Parameter(Mandatory)][string]$EmailFrom,
    [Parameter(Mandatory)][string]$SmtpServer,
    [Parameter()][int]$SmtpPort = 25,
    [Parameter()][switch]$UseSsl,
    [Parameter()][string]$CredentialXmlPath,
    [Parameter()][int]$ThresholdGB = 200,
    [Parameter()][string[]]$DriveLetters = @('C'),
    [Parameter()][int]$ReAlertHours = 24,
    [Parameter()][string]$DailyTime = '3:00AM'
)

$ErrorActionPreference = 'Stop'

$installDir = 'C:\Program Files\DiskSpaceMonitor'
$dataDir    = 'C:\ProgramData\DiskSpaceMonitor'
$taskName   = 'Disk Space Monitor'
$scriptName = 'Invoke-DiskSpaceCheck.ps1'

try {
    foreach ($dir in @($installDir, $dataDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    Start-Transcript -Path (Join-Path $dataDir 'install.log') -Append | Out-Null

    $sourceScript = Join-Path $PSScriptRoot $scriptName
    if (-not (Test-Path $sourceScript)) {
        throw "Source script not found next to the installer: $sourceScript"
    }
    $scriptPath = Join-Path $installDir $scriptName
    Copy-Item -Path $sourceScript -Destination $scriptPath -Force

    $configPath = Join-Path $dataDir 'config.json'
    $config = [ordered]@{
        EmailTo           = $EmailTo
        EmailFrom         = $EmailFrom
        SmtpServer        = $SmtpServer
        SmtpPort          = $SmtpPort
        UseSsl            = [bool]$UseSsl
        CredentialXmlPath = $CredentialXmlPath
        ThresholdGB       = $ThresholdGB
        DriveLetters      = $DriveLetters
        ReAlertHours      = $ReAlertHours
    }
    $config | ConvertTo-Json | Set-Content -Path $configPath -Encoding UTF8
    Write-Output "Config written to $configPath"

    if ($PSCmdlet.ShouldProcess($taskName, 'Register scheduled task')) {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
        $trigger   = New-ScheduledTaskTrigger -Daily -At $DailyTime
        $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

        Register-ScheduledTask -TaskName $taskName `
            -Description 'Monitors free disk space and emails an alert when it falls below the configured threshold.' `
            -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

        Write-Output "Scheduled task '$taskName' registered (daily at $DailyTime, runs as SYSTEM)."
    }

    Write-Output 'Install complete.'
    exit 0
}
catch {
    Write-Error "Install failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
