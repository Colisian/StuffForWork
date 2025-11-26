<#
.SYNOPSIS
    Simple script to retrieve recent user logins using Event Log.

.DESCRIPTION
    A simplified version that shows the last 5 unique users who logged in.

.PARAMETER Count
    Number of login records to display. Default is 5.

.PARAMETER ExcludeUsers
    Array of usernames to exclude from results. Default is @('cmcleod1').

.EXAMPLE
    .\GetLastLoggedOnUsers-Simple.ps1

.EXAMPLE
    .\GetLastLoggedOnUsers-Simple.ps1 -Count 10

.EXAMPLE
    .\GetLastLoggedOnUsers-Simple.ps1 -ExcludeUsers @()
    Shows all users (no exclusions).
#>

param(
    [Parameter(Mandatory=$false)]
    [int]$Count = 5,

    [Parameter(Mandatory=$false)]
    [string[]]$ExcludeUsers = @('cmcleod1')
)

Write-Host "`nRetrieving last $Count user logins..." -ForegroundColor Cyan
if ($ExcludeUsers.Count -gt 0) {
    Write-Host "(Excluding users: $($ExcludeUsers -join ', '))" -ForegroundColor Yellow
}
Write-Host ""

try {
    # Get logon events from Security log
    $logins = Get-EventLog -LogName Security -InstanceId 4624 -Newest 1000 -ErrorAction Stop |
        Where-Object {
            # Filter for interactive and remote desktop logons
            ($_.ReplacementStrings[8] -eq '2' -or $_.ReplacementStrings[8] -eq '10') -and
            $_.ReplacementStrings[5] -notmatch '^(SYSTEM|LOCAL SERVICE|NETWORK SERVICE|DWM-|UMFD-|$)' -and
            $_.ReplacementStrings[5] -ne '-' -and
            $_.ReplacementStrings[5] -notin $ExcludeUsers
        } |
        Select-Object -First $Count |
        ForEach-Object {
            [PSCustomObject]@{
                'Login Time' = $_.TimeGenerated.ToString("yyyy-MM-dd HH:mm:ss")
                'User' = "$($_.ReplacementStrings[6])\$($_.ReplacementStrings[5])"
                'Logon Type' = if ($_.ReplacementStrings[8] -eq '2') { 'Interactive' } else { 'RemoteDesktop' }
                'Workstation' = $_.ReplacementStrings[11]
            }
        }

    if ($logins) {
        $logins | Format-Table -AutoSize
        Write-Host "Total: $($logins.Count) logins shown`n" -ForegroundColor Green
    }
    else {
        Write-Host "No login events found.`n" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Error: $_`n" -ForegroundColor Red
    Write-Host "Note: Run PowerShell as Administrator to access Security logs.`n" -ForegroundColor Yellow
}
