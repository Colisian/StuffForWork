#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Exports all user members of an AD group (including nested groups) to a timestamped CSV.

.DESCRIPTION
    Prompts for (or accepts) an AD group name, resolves it against the domain, and exports
    all nested user members to CSV using an LDAP matching-rule-in-chain query. This avoids
    the Get-ADGroupMember 5,000-member ADWS cap and silently-skipped foreign security
    principals.

    Runs fully interactive (GUI prompts) when launched with no parameters, or fully
    non-interactive when -GroupName is supplied — so it works both double-clicked and
    from an automation/remoting context.

.PARAMETER GroupName
    Group to export (sAMAccountName, CN, or DN). If omitted, an input box (or Read-Host
    fallback) prompts for it. Partial names are resolved via a wildcard search when no
    exact match exists.

.PARAMETER Server
    Domain controller to query. Defaults to OITDC004.AD.UMD.EDU, with automatic
    fallback to any discoverable DC if that one is unreachable.

.PARAMETER ExportFolder
    Destination folder for the CSV. Created if missing. Defaults to C:\Exports.

.EXAMPLE
    .\Export-ADGroupMembers.ps1
    Fully interactive: prompts for the group name, shows result in a message box.

.EXAMPLE
    .\Export-ADGroupMembers.ps1 -GroupName 'LIB-Staff-All' -ExportFolder 'D:\Reports'
    Non-interactive: exports without any GUI prompts and writes the member objects
    to the pipeline as well as the CSV.

.NOTES
    Author  : Oji McLeod (cmcleod1@umd.edu)
    Date    : 2026-07-04
    Version : 2.0
    - LastLogonDate derives from lastLogonTimestamp, which replicates lazily and can
      be up to ~14 days stale. Treat it as "roughly dormant since", not exact.
    - Requires RSAT ActiveDirectory module; Windows only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [string]$GroupName,

    [Parameter()]
    [string]$Server = 'OITDC004.AD.UMD.EDU',

    [Parameter()]
    [string]$ExportFolder = 'C:\Exports'
)

begin {
    $ErrorActionPreference = 'Stop'

    Import-Module ActiveDirectory

    # GUI assemblies are only needed when we run interactively with no -GroupName
    $script:guiAvailable = $false
    if (-not $GroupName -and [Environment]::UserInteractive) {
        try {
            Add-Type -AssemblyName Microsoft.VisualBasic, System.Windows.Forms
            $script:guiAvailable = $true
        }
        catch {
            Write-Verbose 'GUI assemblies unavailable; falling back to console prompts.'
        }
    }

    function Show-UserMessage {
        <#
        .SYNOPSIS
            Shows a message box when GUI is available, otherwise writes to the console.
        .NOTES
            Author: Oji McLeod | Date: 2026-07-04 | Version: 1.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Message,
            [Parameter()][string]$Title = 'Export AD Group Members',
            [Parameter()][ValidateSet('Information', 'Warning', 'Error')][string]$Icon = 'Information'
        )
        if ($script:guiAvailable) {
            [System.Windows.Forms.MessageBox]::Show(
                $Message, $Title,
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::$Icon
            ) | Out-Null
        }
        else {
            switch ($Icon) {
                'Error'   { Write-Error $Message -ErrorAction Continue }
                'Warning' { Write-Warning $Message }
                default   { Write-Host $Message }
            }
        }
    }

    function Get-TargetServer {
        <#
        .SYNOPSIS
            Returns the preferred DC if reachable, otherwise discovers an alternative.
        .NOTES
            Author: Oji McLeod | Date: 2026-07-04 | Version: 1.0
        #>
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$Preferred)

        if (Test-Connection -ComputerName $Preferred -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            return $Preferred
        }
        Write-Warning "Preferred DC $Preferred is unreachable; discovering another domain controller."
        $dc = Get-ADDomainController -Discover -DomainName 'AD.UMD.EDU'
        return [string]$dc.HostName[0]
    }

    function Resolve-TargetGroup {
        <#
        .SYNOPSIS
            Resolves a group by identity, falling back to a wildcard name search.
        .NOTES
            Author: Oji McLeod | Date: 2026-07-04 | Version: 1.0
            Throws with the list of candidates if the name is ambiguous.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Server
        )

        try {
            return Get-ADGroup -Identity $Name -Server $Server
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
            Write-Verbose "No exact match for '$Name'; trying wildcard search."
        }

        $candidates = @(Get-ADGroup -Filter "Name -like '*$Name*' -or SamAccountName -like '*$Name*'" -Server $Server)
        switch ($candidates.Count) {
            0 { throw "No AD group found matching '$Name'." }
            1 {
                Write-Verbose ("Resolved '{0}' to group '{1}'." -f $Name, $candidates[0].Name)
                return $candidates[0]
            }
            default {
                $list = ($candidates.Name | Sort-Object | Select-Object -First 15) -join "`n  "
                throw ("'{0}' is ambiguous — {1} groups match. Be more specific:`n  {2}" -f $Name, $candidates.Count, $list)
            }
        }
    }
}

process {
    try {
        # 1) Get the group name — parameter, GUI input box, or console prompt
        if (-not $GroupName) {
            if ($script:guiAvailable) {
                $GroupName = [Microsoft.VisualBasic.Interaction]::InputBox(
                    'Enter the AD group name (sAMAccountName, CN, DN, or partial name):',
                    'Select AD Group', ''
                )
            }
            else {
                $GroupName = Read-Host 'Enter the AD group name (sAMAccountName, CN, DN, or partial name)'
            }
        }
        if ([string]::IsNullOrWhiteSpace($GroupName)) {
            Show-UserMessage -Message 'No group specified. Exiting.' -Icon Warning
            exit 1
        }

        # 2) Pick a reachable DC and resolve the group
        $targetServer = Get-TargetServer -Preferred $Server
        $group        = Resolve-TargetGroup -Name $GroupName.Trim() -Server $targetServer

        # 3) Recursive membership via matching-rule-in-chain: no 5,000-member ADWS cap,
        #    returns nested users directly, and only user objects (no FSP noise)
        Write-Verbose ("Querying nested members of '{0}' on {1}..." -f $group.Name, $targetServer)
        $members = Get-ADUser -Server $targetServer `
            -LDAPFilter "(memberOf:1.2.840.113556.1.4.1941:=$($group.DistinguishedName))" `
            -Properties DisplayName, EmailAddress, Department, Title, PasswordLastSet, LastLogonDate, Enabled |
            Sort-Object SamAccountName |
            Select-Object SamAccountName, Name, DisplayName,
                          @{Name = 'Email';      Expression = { $_.EmailAddress }},
                          Department, Title, Enabled,
                          @{Name = 'PasswordLastSet'; Expression = { if ($_.PasswordLastSet) { $_.PasswordLastSet.ToString('yyyy-MM-dd') } else { 'Never' } }},
                          @{Name = 'LastLogonDate';   Expression = { if ($_.LastLogonDate)   { $_.LastLogonDate.ToString('yyyy-MM-dd') }   else { 'Never' } }}

        if (-not $members) {
            Show-UserMessage -Message ("Group '{0}' has no user members (nested included). Nothing to export." -f $group.Name) -Icon Warning
            exit 0
        }

        # 4) Timestamped CSV path — never silently clobbers a previous snapshot
        if (-not (Test-Path $ExportFolder)) {
            New-Item -Path $ExportFolder -ItemType Directory -Force | Out-Null
        }
        $safeName = ($group.Name -replace '[\\/:*?"<>|]', '_')
        $csvPath  = Join-Path $ExportFolder ('{0}_Members_{1:yyyyMMdd-HHmmss}.csv' -f $safeName, (Get-Date))

        # 5) Export
        if ($PSCmdlet.ShouldProcess($csvPath, ("Export {0} members of '{1}'" -f @($members).Count, $group.Name))) {
            $members | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

            $disabledCount = @($members | Where-Object { -not $_.Enabled }).Count
            $summary = "Export successful: {0} users ({1} disabled)`n{2}" -f @($members).Count, $disabledCount, $csvPath
            Show-UserMessage -Message $summary

            # Open the export folder when run interactively so the file is easy to find
            if ($script:guiAvailable) {
                Invoke-Item $ExportFolder
            }
        }

        # Emit to the pipeline too, so the script composes with other tooling
        if (-not $script:guiAvailable) {
            $members
        }
    }
    catch {
        Show-UserMessage -Message ("Error exporting group members:`n{0}" -f $_.Exception.Message) -Title 'Export Failed' -Icon Error
        exit 1
    }
}
