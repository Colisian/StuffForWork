<#
.SYNOPSIS
    Retrieves the most recent user logins on the machine.

.DESCRIPTION
    This script queries the Security event log for successful logon events (Event ID 4624)
    and displays the most recent interactive and remote desktop logins.

.PARAMETER ComputerName
    The name of the computer to query. Defaults to local computer.

.PARAMETER Count
    Number of login records to display. Default is 5.

.PARAMETER UniqueUsers
    If specified, shows only the most recent login for each unique user.

.PARAMETER DaysBack
    How many days back to search. Default is 30.

.PARAMETER MaxEvents
    Maximum number of events to search through. Default is 10000.

.PARAMETER ExcludeUsers
    Array of usernames to exclude from results. Default is @('cmcleod1').

.EXAMPLE
    .\GetLastLoggedOnUsers.ps1
    Shows the last 5 logins on the local computer (excluding cmcleod1).

.EXAMPLE
    .\GetLastLoggedOnUsers.ps1 -ComputerName "RemotePC" -UniqueUsers
    Shows the last 5 unique users who logged into RemotePC (excluding cmcleod1).

.EXAMPLE
    .\GetLastLoggedOnUsers.ps1 -Count 10 -UniqueUsers -DaysBack 60
    Shows the last 10 unique users who logged in within the past 60 days.

.EXAMPLE
    .\GetLastLoggedOnUsers.ps1 -ExcludeUsers @('cmcleod1','admin')
    Excludes both cmcleod1 and admin from the results.

.EXAMPLE
    .\GetLastLoggedOnUsers.ps1 -ExcludeUsers @()
    Shows all users (no exclusions).
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory=$false)]
    [int]$Count = 5,

    [Parameter(Mandatory=$false)]
    [switch]$UniqueUsers,

    [Parameter(Mandatory=$false)]
    [int]$DaysBack = 30,

    [Parameter(Mandatory=$false)]
    [int]$MaxEvents = 10000,

    [Parameter(Mandatory=$false)]
    [string[]]$ExcludeUsers = @('cmcleod1')
)

Write-Host "Retrieving last $Count logins from $ComputerName..." -ForegroundColor Cyan
if ($UniqueUsers) {
    Write-Host "(Showing unique users only)" -ForegroundColor Yellow
}
if ($ExcludeUsers.Count -gt 0) {
    Write-Host "(Excluding users: $($ExcludeUsers -join ', '))" -ForegroundColor Yellow
}
Write-Host ""

try {
    # Query Security event log for successful logons (Event ID 4624)
    # Logon Type 2 = Interactive (local logon)
    # Logon Type 10 = RemoteInteractive (Terminal Services, Remote Desktop)

    $startTime = (Get-Date).AddDays(-$DaysBack)

    $events = Get-WinEvent -ComputerName $ComputerName -FilterHashtable @{
        LogName = 'Security'
        ID = 4624
        StartTime = $startTime
    } -MaxEvents $MaxEvents -ErrorAction Stop | Where-Object {
        $xml = [xml]$_.ToXml()
        $logonType = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'LogonType'} | Select-Object -ExpandProperty '#text'
        $targetUserName = $xml.Event.EventData.Data | Where-Object {$_.Name -eq 'TargetUserName'} | Select-Object -ExpandProperty '#text'

        # Filter for interactive (2) and remote desktop (10) logons
        # Exclude system accounts and specified users
        ($logonType -eq '2' -or $logonType -eq '10') -and
        $targetUserName -notmatch '^(SYSTEM|LOCAL SERVICE|NETWORK SERVICE|DWM-\d+|UMFD-\d+)$' -and
        $targetUserName -ne '-' -and
        $targetUserName -notin $ExcludeUsers
    }

    # Parse and format the results
    $logonEvents = $events | ForEach-Object {
        $xml = [xml]$_.ToXml()

        [PSCustomObject]@{
            TimeCreated = $_.TimeCreated
            UserName = ($xml.Event.EventData.Data | Where-Object {$_.Name -eq 'TargetUserName'}).'#text'
            Domain = ($xml.Event.EventData.Data | Where-Object {$_.Name -eq 'TargetDomainName'}).'#text'
            LogonType = switch (($xml.Event.EventData.Data | Where-Object {$_.Name -eq 'LogonType'}).'#text') {
                '2' { 'Interactive' }
                '10' { 'RemoteDesktop' }
                default { $_ }
            }
            SourceIP = ($xml.Event.EventData.Data | Where-Object {$_.Name -eq 'IpAddress'}).'#text'
        }
    } | Sort-Object TimeCreated -Descending

    # Filter for unique users if requested
    if ($UniqueUsers) {
        $seenUsers = @{}
        $logonEvents = $logonEvents | Where-Object {
            $userKey = "$($_.Domain)\$($_.UserName)"
            if (-not $seenUsers.ContainsKey($userKey)) {
                $seenUsers[$userKey] = $true
                $true
            } else {
                $false
            }
        }
    }

    # Select the requested count
    $logonEvents = $logonEvents | Select-Object -First $Count

    if ($logonEvents) {
        $displayTitle = if ($UniqueUsers) { "Last $Count Unique User Logins:" } else { "Last $Count User Logins:" }
        Write-Host $displayTitle -ForegroundColor Green
        Write-Host ("=" * 100) -ForegroundColor Green

        $logonEvents | Format-Table -AutoSize @{
            Label = "Login Time"
            Expression = {$_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")}
        },
        @{
            Label = "User"
            Expression = {"$($_.Domain)\$($_.UserName)"}
        },
        @{
            Label = "Logon Type"
            Expression = {$_.LogonType}
        },
        @{
            Label = "Source IP"
            Expression = {if ($_.SourceIP -eq '-' -or $_.SourceIP -eq '127.0.0.1') { 'Local' } else { $_.SourceIP }}
        }

        Write-Host ""
        Write-Host "Results: $($logonEvents.Count) logins shown (searched through $($events.Count) matching events in last $DaysBack days)" -ForegroundColor Yellow
        if ($events.Count -eq $MaxEvents) {
            Write-Host "Warning: Reached MaxEvents limit ($MaxEvents). Consider increasing -MaxEvents or reducing -DaysBack." -ForegroundColor Magenta
        }
    }
    else {
        Write-Host "No recent login events found." -ForegroundColor Yellow
        Write-Host "Try increasing -DaysBack or -MaxEvents parameters." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Note: This script requires administrative privileges to read the Security event log." -ForegroundColor Yellow
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
}

Write-Host ""
