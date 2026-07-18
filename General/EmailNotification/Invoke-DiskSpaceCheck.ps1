<#
.SYNOPSIS
    Checks free space on fixed drives and sends an email alert when any drive falls below a threshold.

.DESCRIPTION
    Reads settings from a JSON config file written by Install-DiskSpaceMonitor.ps1
    (C:\ProgramData\DiskSpaceMonitor\config.json). Designed to run non-interactively
    as SYSTEM from a scheduled task.

    Mail is sent through an SMTP relay. By default no authentication is used (internal
    relay pattern). If the config specifies CredentialXmlPath, a DPAPI-encrypted
    PSCredential is imported from that file — it must have been exported by the same
    account that runs this script (SYSTEM), on this machine.

    Alerts are throttled: once an alert is sent, no further email goes out until
    ReAlertHours have elapsed, so a persistently low drive does not spam the inbox.

    Logs to C:\ProgramData\DiskSpaceMonitor\DiskSpaceMonitor.log.

.PARAMETER ConfigPath
    Path to the JSON configuration file. Defaults to
    C:\ProgramData\DiskSpaceMonitor\config.json.

.EXAMPLE
    PS> .\Invoke-DiskSpaceCheck.ps1 -Verbose
    Runs a check immediately using the installed configuration.

.NOTES
    Author:  Colisian (cmcleod1@umd.edu)
    Date:    2026-07-14
    Version: 2.0
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath = 'C:\ProgramData\DiskSpaceMonitor\config.json'
)

$ErrorActionPreference = 'Stop'

$dataDir   = 'C:\ProgramData\DiskSpaceMonitor'
$logPath   = Join-Path $dataDir 'DiskSpaceMonitor.log'
$statePath = Join-Path $dataDir 'state.json'

function Get-LowDisk {
    <#
    .SYNOPSIS
        Returns fixed drives whose free space is below the threshold.
    .NOTES
        Author:  Colisian (cmcleod1@umd.edu)
        Date:    2026-07-14
        Version: 2.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$DriveLetters,
        [Parameter(Mandatory)][int]$ThresholdGB
    )

    foreach ($letter in $DriveLetters) {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($letter):'"
        if (-not $disk) {
            Write-Warning "Drive $letter`: not found on this system; skipping."
            continue
        }

        $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        $sizeGB = [math]::Round($disk.Size / 1GB, 2)
        # Write-Host, not Write-Output: this function's output stream is the list of
        # low drives, and status text would be counted as one
        Write-Host "Drive $letter`: $freeGB GB free of $sizeGB GB (threshold $ThresholdGB GB)."

        if ($freeGB -lt $ThresholdGB) {
            [pscustomobject]@{
                Drive  = $letter
                FreeGB = $freeGB
                SizeGB = $sizeGB
            }
        }
    }
}

function Send-AlertMail {
    <#
    .SYNOPSIS
        Sends the low-disk alert email using settings from the config object.
    .NOTES
        Author:  Colisian (cmcleod1@umd.edu)
        Date:    2026-07-14
        Version: 2.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Config,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body
    )

    $mailParams = @{
        To         = @($Config.EmailTo)
        From       = $Config.EmailFrom
        Subject    = $Subject
        Body       = $Body
        SmtpServer = $Config.SmtpServer
        Port       = $Config.SmtpPort
    }

    if ($Config.UseSsl) {
        $mailParams.UseSsl = $true
    }

    if ($Config.CredentialXmlPath) {
        if (-not (Test-Path $Config.CredentialXmlPath)) {
            throw "CredentialXmlPath is set but the file does not exist: $($Config.CredentialXmlPath)"
        }
        $mailParams.Credential = Import-Clixml -Path $Config.CredentialXmlPath
    }

    Send-MailMessage @mailParams
}

try {
    if (-not (Test-Path $dataDir)) {
        New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
    }

    # Rotate the transcript once it passes 5 MB so it never grows unbounded
    if ((Test-Path $logPath) -and ((Get-Item $logPath).Length -gt 5MB)) {
        Move-Item -Path $logPath -Destination "$logPath.old" -Force
    }
    Start-Transcript -Path $logPath -Append | Out-Null

    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found: $ConfigPath. Run Install-DiskSpaceMonitor.ps1 first."
    }
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

    $lowDrives = @(Get-LowDisk -DriveLetters @($config.DriveLetters) -ThresholdGB $config.ThresholdGB)

    if ($lowDrives.Count -eq 0) {
        Write-Output 'All monitored drives are above the threshold. No alert sent.'
        exit 0
    }

    # Throttle: skip the alert if one was already sent within the ReAlertHours window
    $reAlertHours = if ($config.ReAlertHours) { [int]$config.ReAlertHours } else { 24 }
    if (Test-Path $statePath) {
        $state        = Get-Content -Path $statePath -Raw | ConvertFrom-Json
        $hoursSince   = ((Get-Date).ToUniversalTime() - [datetime]$state.LastAlertUtc).TotalHours
        if ($hoursSince -lt $reAlertHours) {
            Write-Output ("Low disk detected, but an alert was already sent {0:N1} hours ago (re-alert window: $reAlertHours h). Skipping." -f $hoursSince)
            exit 0
        }
    }

    $driveLines = $lowDrives | ForEach-Object {
        "  - Drive $($_.Drive): $($_.FreeGB) GB free of $($_.SizeGB) GB"
    }
    $subject = "Low Disk Space Alert on $env:COMPUTERNAME"
    $body    = @"
Warning: the following drive(s) on $env:COMPUTERNAME are below the $($config.ThresholdGB) GB free-space threshold:

$($driveLines -join "`n")

Checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') local time.
This alert repeats at most once every $reAlertHours hours while the condition persists.
"@

    Send-AlertMail -Config $config -Subject $subject -Body $body
    Write-Output "Alert email sent to $($config.EmailTo -join ', ') via $($config.SmtpServer):$($config.SmtpPort)."

    [pscustomobject]@{
        LastAlertUtc = (Get-Date).ToUniversalTime().ToString('o')
        Drives       = $lowDrives
    } | ConvertTo-Json | Set-Content -Path $statePath -Encoding UTF8

    exit 0
}
catch {
    Write-Error "Disk space check failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
