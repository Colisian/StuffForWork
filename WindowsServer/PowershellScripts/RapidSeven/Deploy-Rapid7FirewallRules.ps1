#Requires -Version 5.1
<#
.SYNOPSIS
    Opens all ports on Windows host firewalls for DIT Rapid7 InsightVM security scanning subnet.

.DESCRIPTION
    Creates inbound Windows Firewall rules to allow the DIT security scanning subnet
    (128.8.236.64/27) full access for vulnerability scanning via Rapid7 InsightVM.

    Subnet Details:
        Network:    128.8.236.64/27
        Range:      128.8.236.65 - 128.8.236.94 (30 usable hosts)
        Netmask:    255.255.255.224

    This script creates rules for:
        - All TCP ports inbound
        - All UDP ports inbound

    Per Rapid7 best practices, the following ports are critical for authenticated scans:
        - TCP 135   (RPC/DCOM - WMI initial connection)
        - TCP 139   (NetBIOS Session)
        - TCP 445   (SMB/CIFS - preferred)
        - TCP 49152-65535 (WMI dynamic high ports)

.PARAMETER ComputerName
    Target computer(s) to configure. Defaults to localhost.

.PARAMETER Remove
    Switch to remove the firewall rules instead of creating them.

.PARAMETER WhatIf
    Shows what would happen without making changes.

.EXAMPLE
    # Run locally on a single host
    .\Deploy-Rapid7FirewallRules.ps1

.EXAMPLE
    # Deploy to multiple remote hosts
    .\Deploy-Rapid7FirewallRules.ps1 -ComputerName "LIBWS001", "LIBWS002", "LIBWS003"

.EXAMPLE
    # Remove the rules
    .\Deploy-Rapid7FirewallRules.ps1 -Remove

.EXAMPLE
    # Preview changes without applying
    .\Deploy-Rapid7FirewallRules.ps1 -WhatIf

.NOTES
    Author:     Oji McLeod - UMD Libraries IT
    Reference:  https://docs.rapid7.com/insightvm/authentication-on-windows-best-practices/
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [string[]]$ComputerName = @($env:COMPUTERNAME),

    [switch]$Remove
)

begin {
    #--- Configuration ---#
    $ScanSubnet    = "128.8.236.64/27"
    $RulePrefix    = "DIT-Rapid7-InsightVM"
    $RuleGroupName = "DIT Security Scanning"

    $Rules = @(
        @{
            DisplayName = "$RulePrefix - Allow All TCP Inbound"
            Description = "Allow DIT Rapid7 InsightVM scanning subnet ($ScanSubnet) inbound on all TCP ports. Jira ticket reference."
            Direction   = "Inbound"
            Protocol    = "TCP"
            LocalPort   = "Any"
            RemoteAddress = $ScanSubnet
            Action      = "Allow"
            Profile     = "Domain"
            Group       = $RuleGroupName
            Enabled     = "True"
        },
        @{
            DisplayName = "$RulePrefix - Allow All UDP Inbound"
            Description = "Allow DIT Rapid7 InsightVM scanning subnet ($ScanSubnet) inbound on all UDP ports. Jira ticket reference."
            Direction   = "Inbound"
            Protocol    = "UDP"
            LocalPort   = "Any"
            RemoteAddress = $ScanSubnet
            Action      = "Allow"
            Profile     = "Domain"
            Group       = $RuleGroupName
            Enabled     = "True"
        }
    )

    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
}

process {
    foreach ($Computer in $ComputerName) {
        Write-Host "`n$('=' * 60)" -ForegroundColor Cyan
        Write-Host "  Target: $Computer" -ForegroundColor Cyan
        Write-Host "$('=' * 60)" -ForegroundColor Cyan

        $ScriptBlock = {
            param($Rules, $RulePrefix, $Remove)

            $output = [System.Collections.Generic.List[PSCustomObject]]::new()

            if ($Remove) {
                # --- REMOVE MODE --- #
                $existing = Get-NetFirewallRule -DisplayName "$RulePrefix*" -ErrorAction SilentlyContinue
                if ($existing) {
                    foreach ($rule in $existing) {
                        try {
                            Remove-NetFirewallRule -Name $rule.Name -ErrorAction Stop
                            $output.Add([PSCustomObject]@{
                                Computer = $env:COMPUTERNAME
                                Rule     = $rule.DisplayName
                                Status   = "REMOVED"
                                Error    = $null
                            })
                        }
                        catch {
                            $output.Add([PSCustomObject]@{
                                Computer = $env:COMPUTERNAME
                                Rule     = $rule.DisplayName
                                Status   = "FAILED"
                                Error    = $_.Exception.Message
                            })
                        }
                    }
                }
                else {
                    $output.Add([PSCustomObject]@{
                        Computer = $env:COMPUTERNAME
                        Rule     = "N/A"
                        Status   = "NO RULES FOUND"
                        Error    = $null
                    })
                }
            }
            else {
                # --- CREATE MODE --- #
                foreach ($RuleDef in $Rules) {
                    $existing = Get-NetFirewallRule -DisplayName $RuleDef.DisplayName -ErrorAction SilentlyContinue

                    if ($existing) {
                        # Update existing rule to ensure correct config
                        try {
                            $existing | Set-NetFirewallRule `
                                -RemoteAddress $RuleDef.RemoteAddress `
                                -Enabled ([Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.Enabled]::True) `
                                -ErrorAction Stop

                            $output.Add([PSCustomObject]@{
                                Computer = $env:COMPUTERNAME
                                Rule     = $RuleDef.DisplayName
                                Status   = "UPDATED (already existed)"
                                Error    = $null
                            })
                        }
                        catch {
                            $output.Add([PSCustomObject]@{
                                Computer = $env:COMPUTERNAME
                                Rule     = $RuleDef.DisplayName
                                Status   = "FAILED"
                                Error    = $_.Exception.Message
                            })
                        }
                    }
                    else {
                        # Create new rule
                        try {
                            New-NetFirewallRule `
                                -DisplayName $RuleDef.DisplayName `
                                -Description $RuleDef.Description `
                                -Direction $RuleDef.Direction `
                                -Protocol $RuleDef.Protocol `
                                -LocalPort $RuleDef.LocalPort `
                                -RemoteAddress $RuleDef.RemoteAddress `
                                -Action $RuleDef.Action `
                                -Profile $RuleDef.Profile `
                                -Group $RuleDef.Group `
                                -Enabled ([Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.Enabled]::True) `
                                -ErrorAction Stop | Out-Null

                            $output.Add([PSCustomObject]@{
                                Computer = $env:COMPUTERNAME
                                Rule     = $RuleDef.DisplayName
                                Status   = "CREATED"
                                Error    = $null
                            })
                        }
                        catch {
                            $output.Add([PSCustomObject]@{
                                Computer = $env:COMPUTERNAME
                                Rule     = $RuleDef.DisplayName
                                Status   = "FAILED"
                                Error    = $_.Exception.Message
                            })
                        }
                    }
                }
            }
            return $output
        }

        try {
            if ($Computer -eq $env:COMPUTERNAME) {
                if ($PSCmdlet.ShouldProcess($Computer, "Configure Rapid7 firewall rules")) {
                    $result = @(& $ScriptBlock -Rules $Rules -RulePrefix $RulePrefix -Remove:$Remove)
                    foreach ($r in $result) { $Results.Add($r) }
                }
            }
            else {
                if ($PSCmdlet.ShouldProcess($Computer, "Configure Rapid7 firewall rules (remote)")) {
                    $result = @(Invoke-Command -ComputerName $Computer -ScriptBlock $ScriptBlock `
                        -ArgumentList $Rules, $RulePrefix, $Remove.IsPresent -ErrorAction Stop)
                    foreach ($r in $result) { $Results.Add($r) }
                }
            }
        }
        catch {
            Write-Warning "Failed to connect to $Computer : $($_.Exception.Message)"
            $Results.Add([PSCustomObject]@{
                Computer = $Computer
                Rule     = "N/A"
                Status   = "CONNECTION FAILED"
                Error    = $_.Exception.Message
            })
        }
    }
}

end {
    Write-Host "`n$('=' * 60)" -ForegroundColor Green
    Write-Host "  RESULTS SUMMARY" -ForegroundColor Green
    Write-Host "$('=' * 60)" -ForegroundColor Green

    $Results | Format-Table -AutoSize

    # Quick verification
    if (-not $Remove) {
        Write-Host "`nVerification - Current Rapid7 rules:" -ForegroundColor Yellow
        Get-NetFirewallRule -DisplayName "$RulePrefix*" -ErrorAction SilentlyContinue |
            Select-Object DisplayName, Enabled, Direction, Profile |
            Format-Table -AutoSize
    }
}