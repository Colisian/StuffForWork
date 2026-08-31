<#
.SYNOPSIS
    Creates a read-only migration inventory for a Windows Server.

.DESCRIPTION
    Collects Windows Server, networking, firewall, listening port, installed software,
    Windows feature, service, scheduled task, IIS, certificate, ODBC, SQL Server,
    filesystem, permission, backup, update, and recent error-event metadata.

    The script creates a timestamped evidence folder containing an executive Markdown
    report, detailed CSV files, and a JSON snapshot. It does not back up databases,
    copy application data, export certificate private keys, or read file contents.
    Values whose names indicate passwords, secrets, tokens, or keys are redacted.

    The default General profile is vendor-neutral. The optional Ares profile adds
    Atlas Systems Ares Course Reserves paths, SQL metadata, services, and documented
    port checks. Custom application roots and database patterns can be supplied for
    any other application.

    Run from an elevated 64-bit Windows PowerShell session on the source server.

.PARAMETER ApplicationProfile
    Optional built-in application profile. General performs a vendor-neutral server
    inventory. Ares adds Atlas Systems Ares Course Reserves discovery. Default: General.

.PARAMETER ApplicationName
    Friendly application/workload name to show in the report. This is useful for a
    general inventory of a third-party application without a built-in profile.

.PARAMETER ApplicationRoot
    One or more application/data roots to size, hash configuration metadata under,
    and include in the ACL inventory. Built-in profile roots are added automatically.

.PARAMETER DatabaseNamePattern
    Optional regular expression selecting SQL databases for trigger inventory. With
    no pattern, all non-system databases are included. The Ares profile defaults to
    databases whose names begin with Ares.

.PARAMETER SqlServerInstance
    Optional SQL Server connection target(s), such as SQLHOST or SQLHOST\INSTANCE,
    to query in addition to locally discovered SQL instances. Uses the current
    Windows identity and read-only metadata queries; no SQL password is accepted.

.PARAMETER OutputRoot
    Parent directory for the timestamped inventory folder. Defaults to an
    Server-Migration-Inventory folder beside this script (or in the current directory
    when the script text is pasted into a console).

.PARAMETER IncludeFileInventory
    Records individual file metadata for discovered application, IIS, and SQL roots.
    File contents are never read. Be aware that file names may contain request or
    user identifiers and should be treated as sensitive operational data.

.PARAMETER IncludeFileHashes
    Calculates SHA-256 hashes for individual inventoried files. This implies
    IncludeFileInventory and can considerably increase runtime and disk I/O.

.PARAMETER MaxFileRecords
    Maximum individual file records to collect across all roots. Default: 200000.

.PARAMETER EventLookbackDays
    Number of days of warning/error events to review. Default: 14.

.PARAMETER Quick
    Skips SQL queries, recursive folder sizing, and event-log collection. Useful for
    validating the script before the full elevated run.

.PARAMETER CreateArchive
    Creates a ZIP of the completed evidence folder beside that folder.

.EXAMPLE
    PS> .\Get-WindowsServerMigrationInventory.ps1 -CreateArchive -Verbose
    Performs a general Windows Server inventory and creates a ZIP.

.EXAMPLE
    PS> .\Get-WindowsServerMigrationInventory.ps1 -ApplicationProfile Ares -CreateArchive -Verbose
    Performs an Ares-aware Windows Server inventory and creates a ZIP.

.EXAMPLE
    PS> .\Get-WindowsServerMigrationInventory.ps1 -Quick -Verbose
    Performs a shorter validation run without SQL queries or recursive scans.

.EXAMPLE
    PS> .\Get-WindowsServerMigrationInventory.ps1 -ApplicationName 'Vendor App' -ApplicationRoot 'D:\VendorApp','E:\VendorData' -DatabaseNamePattern '^VendorDb' -CreateArchive
    Adds custom roots and selects matching application databases without a built-in profile.

.NOTES
    Author:  Colisian (cmcleod1@umd.edu)
    Date:    2026-08-30
    Version: 2.0.0

    Security: The output contains infrastructure details, service account names,
    paths, firewall rules, and certificate metadata. Store it in an access-controlled
    location and redact it before attaching it to a vendor or help-desk ticket.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [ValidateSet('General', 'Ares')]
    [string]$ApplicationProfile = 'General',

    [Parameter()]
    [string]$ApplicationName,

    [Parameter()]
    [string[]]$ApplicationRoot = @(),

    [Parameter()]
    [string]$DatabaseNamePattern,

    [Parameter()]
    [string[]]$SqlServerInstance = @(),

    [Parameter()]
    [string]$OutputRoot,

    [Parameter()]
    [switch]$IncludeFileInventory,

    [Parameter()]
    [switch]$IncludeFileHashes,

    [Parameter()]
    [ValidateRange(1, 1000000)]
    [int]$MaxFileRecords = 200000,

    [Parameter()]
    [ValidateRange(1, 90)]
    [int]$EventLookbackDays = 14,

    [Parameter()]
    [switch]$Quick,

    [Parameter()]
    [switch]$CreateArchive
)

$ErrorActionPreference = 'Stop'
$script:collectionWarnings = [System.Collections.Generic.List[string]]::new()
$script:author = 'Colisian (cmcleod1@umd.edu)'
$script:version = '2.0.0'
$script:runDate = Get-Date

$profileDefinition = if ($ApplicationProfile -eq 'Ares') {
    [ordered]@{
        Name            = 'Ares Course Reserves'
        SoftwarePattern = '(?i)(^|[^A-Za-z])Ares([^A-Za-z]|$)|Atlas Systems'
        ServicePattern  = '(?i)(^|[^A-Za-z])Ares([^A-Za-z]|$)|Atlas'
        DatabasePattern = '^Ares'
        DefaultRoots    = @(
            'C:\Ares',
            'C:\AresData',
            'C:\inetpub\wwwroot\Ares'
        )
        AclPaths        = @(
            'C:\Ares',
            'C:\Ares\Web\WebPages',
            'C:\Ares\AresDocs',
            'C:\Ares\AresDocs\PublicDocs',
            'C:\Ares\AresDocs\TempUpload',
            'C:\Ares\Print',
            'C:\Ares\Backup',
            'C:\inetpub\wwwroot\Ares'
        )
    }
}
else {
    [ordered]@{
        Name            = 'Windows Server workload'
        SoftwarePattern = ''
        ServicePattern  = ''
        DatabasePattern = ''
        DefaultRoots    = @()
        AclPaths        = @()
    }
}

if ([string]::IsNullOrWhiteSpace($ApplicationName)) {
    $ApplicationName = $profileDefinition.Name
}
if ([string]::IsNullOrWhiteSpace($DatabaseNamePattern)) {
    $DatabaseNamePattern = $profileDefinition.DatabasePattern
}
$effectiveApplicationRoots = @($profileDefinition.DefaultRoots) + @($ApplicationRoot)
$applicationMatchPattern = if ($profileDefinition.SoftwarePattern) {
    $profileDefinition.SoftwarePattern
}
elseif ($ApplicationName -ne 'Windows Server workload') {
    [regex]::Escape($ApplicationName)
}
else {
    ''
}

function Add-CollectionWarning {
    <#
    .SYNOPSIS
        Adds a non-fatal collection warning to the report.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $script:collectionWarnings.Add($Message)
    Write-Warning $Message
}

function ConvertTo-SafeText {
    <#
    .SYNOPSIS
        Converts a value to one line of text and redacts secret-like values.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value,

        [Parameter()]
        [string]$Name = ''
    )

    if ($Name -match '(?i)(password|passwd|pwd|secret|token|api.?key|private.?key|connection.?string|credential)') {
        return '[REDACTED]'
    }

    if ($null -eq $Value) {
        return ''
    }

    $text = if ($Value -is [System.Array]) { $Value -join '; ' } else { [string]$Value }
    $text = $text -replace '[\r\n]+', ' '
    $text = $text -replace '(?i)(password|passwd|pwd|secret|token|api[_-]?key)\s*[=:]\s*[^;\s]+', '$1=[REDACTED]'
    return $text.Trim()
}

function ConvertTo-MarkdownCell {
    <#
    .SYNOPSIS
        Escapes a value for use in a compact Markdown table cell.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    $text = ConvertTo-SafeText -Value $Value
    return ($text -replace '\|', '\|')
}

function Export-InventoryCsv {
    <#
    .SYNOPSIS
        Exports a non-empty inventory collection to a CSV file.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Data,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (@($Data).Count -eq 0) {
        return
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Export inventory CSV')) {
        $Data | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8
    }
}

function Get-RegistryInstalledSoftware {
    <#
    .SYNOPSIS
        Reads installed application metadata without invoking Win32_Product.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$TargetDatabasePattern = '',

        [Parameter()]
        [ValidateSet('General', 'Ares')]
        [string]$Profile = 'General',

        [Parameter()]
        [string[]]$AdditionalServerInstance = @()
    )

    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $items = foreach ($registryPath in $registryPaths) {
        Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue | Where-Object DisplayName | ForEach-Object {
            [pscustomobject]@{
                DisplayName     = $_.DisplayName
                DisplayVersion  = $_.DisplayVersion
                Publisher       = $_.Publisher
                InstallDate     = $_.InstallDate
                InstallLocation = $_.InstallLocation
                Architecture    = if ($_.PSPath -match 'WOW6432Node') { '32-bit' } else { '64-bit' }
                ProductCode     = $_.PSChildName
                UninstallType   = if ($_.WindowsInstaller -eq 1) { 'MSI' } else { 'Other' }
            }
        }
    }

    return @($items | Sort-Object DisplayName, DisplayVersion -Unique)
}

function Get-WindowsFeatureInventory {
    <#
    .SYNOPSIS
        Returns installed Windows Server roles and features.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    try {
        $osProductType = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).ProductType
        if ($osProductType -ne 1 -and (Get-Command -Name Get-WindowsFeature -ErrorAction SilentlyContinue)) {
            return @(Get-WindowsFeature | Where-Object Installed | Select-Object Name, DisplayName, FeatureType, InstallState)
        }

        return @(Get-WindowsOptionalFeature -Online -ErrorAction Stop |
            Where-Object State -eq 'Enabled' |
            Select-Object FeatureName, State)
    }
    catch {
        Add-CollectionWarning -Message "Windows role/feature inventory failed: $($_.Exception.Message)"
        return @()
    }
}

function Get-FirewallInventory {
    <#
    .SYNOPSIS
        Returns enabled Windows Firewall rules and their associated filters.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name Get-NetFirewallRule -ErrorAction SilentlyContinue)) {
        Add-CollectionWarning -Message 'NetSecurity commands are unavailable; firewall rules were not collected.'
        return @()
    }

    # Asking four associated-filter commands once per rule is extremely slow on hosts
    # with hundreds of rules. Collect filters in bulk and query address scope only for
    # rules that match migration-relevant ports or product names.
    $rules = @(Get-NetFirewallRule -Enabled True -PolicyStore ActiveStore -ErrorAction Stop)
    $portFilters = @(Get-NetFirewallPortFilter -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
    $applicationFilters = @(Get-NetFirewallApplicationFilter -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
    $serviceFilters = @(Get-NetFirewallServiceFilter -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
    if ($rules.Count -gt 0 -and $portFilters.Count -eq 0) {
        Add-CollectionWarning -Message 'Firewall rules were returned, but associated port filters could not be read. Run elevated and treat firewall port matching as incomplete.'
    }

    $portById = @{}
    foreach ($filter in $portFilters) { $portById[$filter.InstanceID] = $filter }
    $applicationById = @{}
    foreach ($filter in $applicationFilters) { $applicationById[$filter.InstanceID] = $filter }
    $serviceById = @{}
    foreach ($filter in $serviceFilters) { $serviceById[$filter.InstanceID] = $filter }

    $migrationPortPattern = '(^|,|\s)(20|21|25|80|389|443|636|1433|3389|4500)($|,|\s)'
    $results = foreach ($rule in $rules) {
        $portFilter = $portById[$rule.InstanceID]
        $applicationFilter = $applicationById[$rule.InstanceID]
        $serviceFilter = $serviceById[$rule.InstanceID]
        $addressFilter = $null
        $collectAddressScope = ([string]$portFilter.LocalPort -match $migrationPortPattern) -or
            ($rule.DisplayName -match '(?i)Ares|Atlas|SQL|IIS|World Wide Web|SMTP|LDAP|Remote Desktop')
        if ($collectAddressScope) {
            $addressFilter = $rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
        }

        [pscustomobject]@{
            DisplayName   = $rule.DisplayName
            Name          = $rule.Name
            Group         = $rule.DisplayGroup
            Direction     = $rule.Direction
            Action        = $rule.Action
            Profile       = ConvertTo-SafeText -Value $rule.Profile
            Protocol      = ConvertTo-SafeText -Value $portFilter.Protocol
            LocalPort     = ConvertTo-SafeText -Value $portFilter.LocalPort
            RemotePort    = ConvertTo-SafeText -Value $portFilter.RemotePort
            LocalAddress  = ConvertTo-SafeText -Value $addressFilter.LocalAddress
            RemoteAddress = ConvertTo-SafeText -Value $addressFilter.RemoteAddress
            Program       = ConvertTo-SafeText -Value $applicationFilter.Program
            Service       = ConvertTo-SafeText -Value $serviceFilter.Service
            AddressScopeCollected = $collectAddressScope
            EdgeTraversal = $rule.EdgeTraversalPolicy
            PolicyStore   = $rule.PolicyStoreSourceType
        }
    }

    return @($results | Sort-Object Direction, LocalPort, DisplayName)
}

function Get-ListeningEndpointInventory {
    <#
    .SYNOPSIS
        Correlates listening TCP and UDP endpoints with owning processes.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    $results = [System.Collections.Generic.List[object]]::new()
    $processCache = @{}

    function Resolve-EndpointProcess {
        <#
        .SYNOPSIS
            Resolves endpoint process metadata and caches it by PID.
        .NOTES
            Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [uint32]$ProcessId
        )

        if (-not $processCache.ContainsKey($ProcessId)) {
            $process = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
            $processCache[$ProcessId] = [pscustomobject]@{
                ProcessName = $process.Name
                ProcessPath = $process.ExecutablePath
                CommandLine = ConvertTo-SafeText -Value $process.CommandLine -Name 'CommandLine'
            }
        }
        return $processCache[$ProcessId]
    }

    if (Get-Command -Name Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        foreach ($endpoint in (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue)) {
            $process = Resolve-EndpointProcess -ProcessId $endpoint.OwningProcess
            $results.Add([pscustomobject]@{
                Protocol      = 'TCP'
                LocalAddress  = $endpoint.LocalAddress
                LocalPort     = $endpoint.LocalPort
                ProcessId     = $endpoint.OwningProcess
                ProcessName   = $process.ProcessName
                ProcessPath   = $process.ProcessPath
                CommandLine   = $process.CommandLine
            })
        }
    }

    if (Get-Command -Name Get-NetUDPEndpoint -ErrorAction SilentlyContinue) {
        foreach ($endpoint in (Get-NetUDPEndpoint -ErrorAction SilentlyContinue)) {
            $process = Resolve-EndpointProcess -ProcessId $endpoint.OwningProcess
            $results.Add([pscustomobject]@{
                Protocol      = 'UDP'
                LocalAddress  = $endpoint.LocalAddress
                LocalPort     = $endpoint.LocalPort
                ProcessId     = $endpoint.OwningProcess
                ProcessName   = $process.ProcessName
                ProcessPath   = $process.ProcessPath
                CommandLine   = $process.CommandLine
            })
        }
    }

    return @($results | Sort-Object Protocol, LocalPort, LocalAddress)
}

function Get-ScheduledTaskInventory {
    <#
    .SYNOPSIS
        Returns scheduled-task identity, principal, action, and trigger metadata.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        Add-CollectionWarning -Message 'ScheduledTasks commands are unavailable; scheduled tasks were not collected.'
        return @()
    }

    $results = foreach ($task in (Get-ScheduledTask -ErrorAction Stop)) {
        $taskInfo = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        $actions = foreach ($action in @($task.Actions)) {
            $actionText = "Execute=$($action.Execute); Arguments=$($action.Arguments); WorkingDirectory=$($action.WorkingDirectory)"
            ConvertTo-SafeText -Value $actionText -Name 'TaskAction'
        }
        $triggers = foreach ($trigger in @($task.Triggers)) {
            $triggerText = "Type=$($trigger.CimClass.CimClassName); StartBoundary=$($trigger.StartBoundary); Enabled=$($trigger.Enabled); RepetitionInterval=$($trigger.Repetition.Interval)"
            ConvertTo-SafeText -Value $triggerText
        }

        [pscustomobject]@{
            TaskPath       = $task.TaskPath
            TaskName       = $task.TaskName
            State          = $task.State
            Author         = $task.Author
            UserId         = $task.Principal.UserId
            LogonType      = $task.Principal.LogonType
            RunLevel       = $task.Principal.RunLevel
            Actions        = $actions -join ' | '
            Triggers       = $triggers -join ' | '
            LastRunTime    = $taskInfo.LastRunTime
            LastTaskResult = $taskInfo.LastTaskResult
            NextRunTime    = $taskInfo.NextRunTime
        }
    }

    return @($results | Sort-Object TaskPath, TaskName)
}

function Get-IisInventory {
    <#
    .SYNOPSIS
        Returns IIS site, application, virtual directory, pool, and binding metadata.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    $result = [ordered]@{
        Available          = $false
        Sites              = @()
        Applications       = @()
        VirtualDirectories = @()
        ApplicationPools   = @()
        Bindings           = @()
        Authentication     = @()
        ContentRoots       = @()
    }

    try {
        Import-Module WebAdministration -ErrorAction Stop
        $result.Available = $true

        $sites = @(Get-Website -ErrorAction Stop)
        $result.Sites = @($sites | ForEach-Object {
            [pscustomobject]@{
                Name         = $_.Name
                Id           = $_.Id
                State        = $_.State
                PhysicalPath = [Environment]::ExpandEnvironmentVariables($_.PhysicalPath)
                Bindings     = ConvertTo-SafeText -Value $_.Bindings.Collection.BindingInformation
                LogFile      = $_.LogFile.Directory
            }
        })

        $result.Applications = @(Get-WebApplication -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                Site         = $_.ItemXPath -replace ".*site\[@name='([^']+)'.*", '$1'
                Path         = $_.Path
                PhysicalPath = [Environment]::ExpandEnvironmentVariables($_.PhysicalPath)
                AppPool      = $_.ApplicationPool
                EnabledProtocols = $_.EnabledProtocols
            }
        })

        $result.VirtualDirectories = @(Get-WebVirtualDirectory -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                ItemXPath    = $_.ItemXPath
                Path         = $_.Path
                PhysicalPath = [Environment]::ExpandEnvironmentVariables($_.PhysicalPath)
            }
        })

        $result.ApplicationPools = @(Get-ChildItem IIS:\AppPools -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                Name                  = $_.Name
                State                 = $_.State
                ManagedRuntimeVersion = $_.managedRuntimeVersion
                ManagedPipelineMode   = $_.managedPipelineMode
                StartMode             = $_.startMode
                IdentityType          = $_.processModel.identityType
                UserName              = $_.processModel.userName
                Enable32BitAppOnWin64 = $_.enable32BitAppOnWin64
                AutoStart             = $_.autoStart
            }
        })

        $bindingItems = [System.Collections.Generic.List[object]]::new()
        foreach ($site in $sites) {
            foreach ($binding in @(Get-WebBinding -Name $site.Name -ErrorAction SilentlyContinue)) {
                $certificate = $null
                $thumbprint = ''
                if ($binding.certificateHash) {
                    $thumbprint = if ($binding.certificateHash -is [byte[]]) {
                        ([BitConverter]::ToString($binding.certificateHash)).Replace('-', '')
                    }
                    else {
                        ([string]$binding.certificateHash).Replace(' ', '').Replace('-', '')
                    }
                    $certificate = Get-Item -LiteralPath "Cert:\LocalMachine\My\$thumbprint" -ErrorAction SilentlyContinue
                }
                $bindingItems.Add([pscustomobject]@{
                    Site              = $site.Name
                    Protocol          = $binding.Protocol
                    BindingInformation = $binding.BindingInformation
                    SslFlags          = $binding.sslFlags
                    CertificateThumbprint = $thumbprint
                    CertificateSubject = $certificate.Subject
                    CertificateExpires = $certificate.NotAfter
                })
            }
        }
        $result.Bindings = @($bindingItems)

        $authenticationItems = [System.Collections.Generic.List[object]]::new()
        $authenticationSections = @(
            'anonymousAuthentication',
            'basicAuthentication',
            'windowsAuthentication',
            'digestAuthentication',
            'clientCertificateMappingAuthentication',
            'iisClientCertificateMappingAuthentication'
        )
        foreach ($site in $sites) {
            foreach ($authenticationSection in $authenticationSections) {
                try {
                    $enabled = Get-WebConfigurationProperty -PSPath 'IIS:\' -Location $site.Name -Filter "system.webServer/security/authentication/$authenticationSection" -Name enabled -ErrorAction Stop
                    $authenticationItems.Add([pscustomobject]@{
                        Site       = $site.Name
                        Method     = $authenticationSection
                        Enabled    = [bool]$enabled.Value
                        QueryError = ''
                    })
                }
                catch {
                    $authenticationItems.Add([pscustomobject]@{
                        Site       = $site.Name
                        Method     = $authenticationSection
                        Enabled    = $null
                        QueryError = $_.Exception.Message
                    })
                }
            }
        }
        $result.Authentication = @($authenticationItems)

        $roots = @($result.Sites.PhysicalPath) + @($result.Applications.PhysicalPath) + @($result.VirtualDirectories.PhysicalPath)
        $result.ContentRoots = @($roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique)
    }
    catch {
        Add-CollectionWarning -Message "IIS inventory failed or IIS is not installed: $($_.Exception.Message)"
    }

    return $result
}

function Get-CertificateInventory {
    <#
    .SYNOPSIS
        Returns Local Computer certificate metadata without exporting certificates.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    try {
        return @(Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                Subject           = $_.Subject
                DnsNames          = ConvertTo-SafeText -Value $_.DnsNameList.Unicode
                Issuer            = $_.Issuer
                Thumbprint        = $_.Thumbprint
                SerialNumber      = $_.SerialNumber
                NotBefore         = $_.NotBefore
                NotAfter          = $_.NotAfter
                HasPrivateKey     = $_.HasPrivateKey
                FriendlyName      = $_.FriendlyName
                EnhancedKeyUsage  = ConvertTo-SafeText -Value $_.EnhancedKeyUsageList.FriendlyName
            }
        })
    }
    catch {
        Add-CollectionWarning -Message "Certificate inventory failed: $($_.Exception.Message)"
        return @()
    }
}

function Get-OdbcInventory {
    <#
    .SYNOPSIS
        Returns machine ODBC DSN metadata with secret-like properties redacted.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    $results = [System.Collections.Generic.List[object]]::new()
    $roots = @(
        @{ Path = 'HKLM:\SOFTWARE\ODBC\ODBC.INI'; Platform = '64-bit' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\ODBC\ODBC.INI'; Platform = '32-bit' }
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root.Path)) {
            continue
        }

        foreach ($dsnKey in (Get-ChildItem -LiteralPath $root.Path -ErrorAction SilentlyContinue | Where-Object PSChildName -ne 'ODBC Data Sources')) {
            $properties = Get-ItemProperty -LiteralPath $dsnKey.PSPath -ErrorAction SilentlyContinue
            foreach ($property in $properties.PSObject.Properties | Where-Object Name -notmatch '^PS') {
                $results.Add([pscustomobject]@{
                    DsnName   = $dsnKey.PSChildName
                    Platform  = $root.Platform
                    Property  = $property.Name
                    Value     = ConvertTo-SafeText -Value $property.Value -Name $property.Name
                })
            }
        }
    }

    return @($results | Sort-Object DsnName, Platform, Property)
}

function Get-SqlInstanceInventory {
    <#
    .SYNOPSIS
        Discovers local SQL instances and queries migration-relevant metadata.
    .DESCRIPTION
        Uses integrated Windows authentication and read-only SELECT queries. Query
        failure is recorded as a warning and does not stop the overall inventory.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    $bundle = [ordered]@{
        Instances       = @()
        Databases       = @()
        DatabaseFiles   = @()
        BackupHistory   = @()
        AgentJobs       = @()
        DatabaseTriggers = @()
        AresPathSettings = @()
    }

    $instanceKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    )
    $instanceNames = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $instanceKeys) {
        if (Test-Path -LiteralPath $key) {
            $properties = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
            foreach ($property in $properties.PSObject.Properties | Where-Object Name -notmatch '^PS') {
                if (-not $instanceNames.Contains($property.Name)) {
                    $instanceNames.Add($property.Name)
                }
            }
        }
    }

    function Invoke-InventorySqlQuery {
        <#
        .SYNOPSIS
            Runs one read-only SQL query using integrated authentication.
        .NOTES
            Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$ServerInstance,
            [Parameter(Mandatory)][string]$Query
        )

        $connectionString = "Server=$ServerInstance;Database=master;Integrated Security=SSPI;Encrypt=True;TrustServerCertificate=True;Application Name=ServerMigrationInventory;Connection Timeout=8"
        $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 30
        $table = [System.Data.DataTable]::new()
        try {
            $connection.Open()
            $reader = $command.ExecuteReader()
            $table.Load($reader)
            return @($table.Rows | ForEach-Object {
                $row = [ordered]@{}
                foreach ($column in $table.Columns) {
                    $row[$column.ColumnName] = $_[$column.ColumnName]
                }
                [pscustomobject]$row
            })
        }
        finally {
            $connection.Dispose()
        }
    }

    $serverTargets = [System.Collections.Generic.List[string]]::new()
    foreach ($instanceName in $instanceNames) {
        $localTarget = if ($instanceName -eq 'MSSQLSERVER') { 'localhost' } else { "localhost\$instanceName" }
        if (-not $serverTargets.Contains($localTarget)) { $serverTargets.Add($localTarget) }
    }
    foreach ($additionalTarget in $AdditionalServerInstance) {
        if (-not [string]::IsNullOrWhiteSpace($additionalTarget) -and -not $serverTargets.Contains($additionalTarget)) {
            $serverTargets.Add($additionalTarget)
        }
    }

    foreach ($serverInstance in $serverTargets) {
        try {
            $serverInfo = Invoke-InventorySqlQuery -ServerInstance $serverInstance -Query @'
SELECT
    CAST(SERVERPROPERTY('ServerName') AS nvarchar(256)) AS ServerName,
    CAST(SERVERPROPERTY('InstanceName') AS nvarchar(256)) AS InstanceName,
    CAST(SERVERPROPERTY('Edition') AS nvarchar(256)) AS Edition,
    CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) AS ProductVersion,
    CAST(SERVERPROPERTY('ProductLevel') AS nvarchar(128)) AS ProductLevel,
    CAST(SERVERPROPERTY('Collation') AS nvarchar(256)) AS Collation,
    CAST(SERVERPROPERTY('IsIntegratedSecurityOnly') AS int) AS IsIntegratedSecurityOnly,
    CAST(SERVERPROPERTY('IsClustered') AS int) AS IsClustered;
'@
            $bundle.Instances += @($serverInfo | ForEach-Object {
                $_ | Add-Member -NotePropertyName ConnectionTarget -NotePropertyValue $serverInstance -PassThru
            })

            $databases = Invoke-InventorySqlQuery -ServerInstance $serverInstance -Query @'
SELECT
    @@SERVERNAME AS SqlServer,
    d.name AS DatabaseName,
    d.state_desc AS State,
    d.recovery_model_desc AS RecoveryModel,
    d.compatibility_level AS CompatibilityLevel,
    d.collation_name AS Collation,
    d.create_date AS CreateDate,
    d.user_access_desc AS UserAccess,
    d.is_read_only AS IsReadOnly,
    CAST(SUM(mf.size) * 8.0 / 1024 AS decimal(18,2)) AS AllocatedMB
FROM sys.databases d
LEFT JOIN sys.master_files mf ON d.database_id = mf.database_id
GROUP BY d.name, d.state_desc, d.recovery_model_desc, d.compatibility_level,
         d.collation_name, d.create_date, d.user_access_desc, d.is_read_only
ORDER BY d.name;
'@
            $bundle.Databases += $databases

            $bundle.DatabaseFiles += Invoke-InventorySqlQuery -ServerInstance $serverInstance -Query @'
SELECT
    @@SERVERNAME AS SqlServer,
    DB_NAME(database_id) AS DatabaseName,
    name AS LogicalName,
    type_desc AS FileType,
    physical_name AS PhysicalPath,
    CAST(size * 8.0 / 1024 AS decimal(18,2)) AS SizeMB,
    growth AS GrowthValue,
    is_percent_growth AS IsPercentGrowth
FROM sys.master_files
ORDER BY DB_NAME(database_id), type_desc;
'@

            $bundle.BackupHistory += Invoke-InventorySqlQuery -ServerInstance $serverInstance -Query @'
WITH LatestBackups AS (
    SELECT
        bs.database_name,
        bs.type,
        bs.backup_start_date,
        bs.backup_finish_date,
        bs.is_copy_only,
        bmf.physical_device_name,
        ROW_NUMBER() OVER (PARTITION BY bs.database_name, bs.type ORDER BY bs.backup_finish_date DESC) AS rn
    FROM msdb.dbo.backupset bs
    LEFT JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
)
SELECT
    @@SERVERNAME AS SqlServer,
    database_name AS DatabaseName,
    CASE type WHEN 'D' THEN 'Full' WHEN 'I' THEN 'Differential' WHEN 'L' THEN 'Log' ELSE type END AS BackupType,
    backup_start_date AS BackupStart,
    backup_finish_date AS BackupFinish,
    is_copy_only AS IsCopyOnly,
    physical_device_name AS BackupPath
FROM LatestBackups
WHERE rn = 1
ORDER BY database_name, type;
'@

            $bundle.AgentJobs += Invoke-InventorySqlQuery -ServerInstance $serverInstance -Query @'
SELECT
    @@SERVERNAME AS SqlServer,
    j.name AS JobName,
    j.enabled AS Enabled,
    SUSER_SNAME(j.owner_sid) AS Owner,
    c.name AS Category,
    h.run_date AS LastRunDate,
    h.run_time AS LastRunTime,
    h.run_status AS LastRunStatus,
    h.message AS LastRunMessage
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.syscategories c ON j.category_id = c.category_id
OUTER APPLY (
    SELECT TOP (1) run_date, run_time, run_status, message
    FROM msdb.dbo.sysjobhistory h
    WHERE h.job_id = j.job_id AND h.step_id = 0
    ORDER BY h.instance_id DESC
) h
ORDER BY j.name;
'@

            $targetDatabases = if ([string]::IsNullOrWhiteSpace($TargetDatabasePattern)) {
                @($databases | Where-Object DatabaseName -notin 'master', 'model', 'msdb', 'tempdb')
            }
            else {
                @($databases | Where-Object DatabaseName -match $TargetDatabasePattern)
            }

            foreach ($database in $targetDatabases) {
                $escapedDatabase = ([string]$database.DatabaseName).Replace(']', ']]')
                $bundle.DatabaseTriggers += Invoke-InventorySqlQuery -ServerInstance $serverInstance -Query @"
SELECT
    @@SERVERNAME AS SqlServer,
    DB_NAME() AS QueryDatabase,
    N'$($database.DatabaseName.Replace("'", "''"))' AS DatabaseName,
    s.name AS SchemaName,
    OBJECT_NAME(t.parent_id, DB_ID(N'$($database.DatabaseName.Replace("'", "''"))')) AS ParentObject,
    t.name AS TriggerName,
    t.is_disabled AS IsDisabled,
    t.is_instead_of_trigger AS IsInsteadOfTrigger,
    t.create_date AS CreateDate,
    t.modify_date AS ModifyDate
FROM [$escapedDatabase].sys.triggers t
LEFT JOIN [$escapedDatabase].sys.objects o ON t.parent_id = o.object_id
LEFT JOIN [$escapedDatabase].sys.schemas s ON o.schema_id = s.schema_id
ORDER BY s.name, t.name;
"@

                if ($Profile -eq 'Ares') {
                    try {
                    $bundle.AresPathSettings += Invoke-InventorySqlQuery -ServerInstance $serverInstance -Query @"
SELECT TOP (500)
    @@SERVERNAME AS SqlServer,
    N'$($database.DatabaseName.Replace("'", "''"))' AS DatabaseName,
    CustKey,
    CASE
        WHEN CustKey LIKE '%Password%' OR CustKey LIKE '%Secret%' OR CustKey LIKE '%Token%' OR CustKey LIKE '%Key' THEN '[REDACTED]'
        ELSE CAST(CustValue AS nvarchar(4000))
    END AS CustValue
FROM [$escapedDatabase].dbo.Customization
WHERE CustKey LIKE '%Path%'
   OR CustKey LIKE '%URL%'
   OR CustKey LIKE '%Server%'
   OR CustKey IN ('AresPhysicalDocPath', 'TempUploadPath', 'AresDocsPath')
ORDER BY CustKey;
"@
                    }
                    catch {
                        Add-CollectionWarning -Message "Could not query Ares path customization metadata in $($database.DatabaseName): $($_.Exception.Message)"
                    }
                }
            }
        }
        catch {
            Add-CollectionWarning -Message "SQL metadata query failed for $serverInstance. Run under an account with SQL metadata access or ask the DBA for the equivalent inventory. Error: $($_.Exception.Message)"
            $bundle.Instances += [pscustomobject]@{
                ConnectionTarget = $serverInstance
                QueryStatus      = 'Failed'
                Error            = $_.Exception.Message
            }
        }
    }

    if ($serverTargets.Count -eq 0) {
        Add-CollectionWarning -Message 'No local SQL Server Database Engine instance was discovered in the standard registry locations. The application may use a remote SQL host or another database platform.'
    }

    return $bundle
}

function Get-FolderMigrationInventory {
    <#
    .SYNOPSIS
        Summarizes migration roots and optionally returns individual file metadata.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Roots,
        [Parameter()][switch]$IncludeFiles,
        [Parameter()][switch]$IncludeHashes,
        [Parameter(Mandatory)][int]$MaximumFileRecords
    )

    $summary = [System.Collections.Generic.List[object]]::new()
    $files = [System.Collections.Generic.List[object]]::new()
    $fileCount = 0
    $truncated = $false

    foreach ($root in ($Roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique)) {
        Write-Verbose "Scanning migration root: $root"
        $rootFiles = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue)
        $totalBytes = ($rootFiles | Measure-Object -Property Length -Sum).Sum
        $latestWrite = ($rootFiles | Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum
        $summary.Add([pscustomobject]@{
            Root              = $root
            FileCount         = $rootFiles.Count
            TotalSizeGB       = [math]::Round(($totalBytes / 1GB), 3)
            LatestWriteUtc    = $latestWrite
            WebConfigCount    = @($rootFiles | Where-Object Name -ieq 'web.config').Count
            DbcFileCount      = @($rootFiles | Where-Object Extension -ieq '.dbc').Count
            BackupFileCount   = @($rootFiles | Where-Object Extension -in '.bak', '.trn', '.dif').Count
        })

        if (-not $IncludeFiles) {
            continue
        }

        foreach ($file in $rootFiles) {
            if ($fileCount -ge $MaximumFileRecords) {
                $truncated = $true
                break
            }
            $hash = ''
            if ($IncludeHashes) {
                try {
                    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                }
                catch {
                    $hash = "ERROR: $($_.Exception.Message)"
                }
            }
            $version = $file.VersionInfo.FileVersion
            $files.Add([pscustomobject]@{
                Root             = $root
                FullName         = $file.FullName
                RelativePath     = $file.FullName.Substring($root.TrimEnd('\').Length).TrimStart('\')
                Length           = $file.Length
                LastWriteTimeUtc = $file.LastWriteTimeUtc
                FileVersion      = $version
                SHA256           = $hash
            })
            $fileCount++
        }

        if ($truncated) {
            break
        }
    }

    if ($truncated) {
        Add-CollectionWarning -Message "Individual file inventory reached MaxFileRecords ($MaximumFileRecords) and was truncated. Folder totals were still collected."
    }

    return [ordered]@{
        Summary   = @($summary)
        Files     = @($files)
        Truncated = $truncated
    }
}

function Get-PathAclInventory {
    <#
    .SYNOPSIS
        Returns explicit and inherited ACL entries for important migration roots.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Paths
    )

    $results = foreach ($path in ($Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique)) {
        try {
            $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
            foreach ($entry in $acl.Access) {
                [pscustomobject]@{
                    Path              = $path
                    Owner             = $acl.Owner
                    IdentityReference = $entry.IdentityReference
                    FileSystemRights  = $entry.FileSystemRights
                    AccessControlType = $entry.AccessControlType
                    IsInherited       = $entry.IsInherited
                    InheritanceFlags  = $entry.InheritanceFlags
                    PropagationFlags  = $entry.PropagationFlags
                }
            }
        }
        catch {
            Add-CollectionWarning -Message "ACL inventory failed for ${path}: $($_.Exception.Message)"
        }
    }

    return @($results)
}

function Get-RecentServerEventInventory {
    <#
    .SYNOPSIS
        Returns a bounded set of recent server and update warning/error events.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$LookbackDays
    )

    $startTime = (Get-Date).AddDays(-$LookbackDays)
    $logs = @(
        'System',
        'Application',
        'Setup',
        'Microsoft-Windows-WindowsUpdateClient/Operational',
        'Microsoft-Windows-Servicing/Operational'
    )
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($logName in $logs) {
        try {
            $events = Get-WinEvent -FilterHashtable @{ LogName = $logName; StartTime = $startTime; Level = 1, 2, 3 } -MaxEvents 500 -ErrorAction Stop
            foreach ($event in $events) {
                $results.Add([pscustomobject]@{
                    LogName      = $logName
                    TimeCreated  = $event.TimeCreated
                    Level        = $event.LevelDisplayName
                    Provider     = $event.ProviderName
                    EventId      = $event.Id
                    RecordId     = $event.RecordId
                    Message      = ConvertTo-SafeText -Value $event.Message -Name 'EventMessage'
                })
            }
        }
        catch {
            Add-CollectionWarning -Message "Event log '$logName' could not be queried: $($_.Exception.Message)"
        }
    }

    return @($results | Sort-Object TimeCreated -Descending)
}

function Get-PendingRebootState {
    <#
    .SYNOPSIS
        Checks common registry indicators for a pending Windows reboot.
    .NOTES
        Author: Colisian | Date: 2026-08-29 | Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    $indicators = [ordered]@{
        ComponentBasedServicing = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        WindowsUpdate           = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        PendingFileRename       = $false
        ComputerRename          = $false
    }

    $sessionManager = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
    $indicators.PendingFileRename = $null -ne $sessionManager.PendingFileRenameOperations

    $activeName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction SilentlyContinue).ComputerName
    $pendingName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction SilentlyContinue).ComputerName
    $indicators.ComputerRename = $activeName -ne $pendingName

    return [pscustomobject]@{
        PendingReboot             = $indicators.Values -contains $true
        ComponentBasedServicing   = $indicators.ComponentBasedServicing
        WindowsUpdate             = $indicators.WindowsUpdate
        PendingFileRename         = $indicators.PendingFileRename
        ComputerRename            = $indicators.ComputerRename
    }
}

# Establish a safe output location.
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not $OutputRoot) {
    $OutputRoot = Join-Path -Path $scriptDir -ChildPath 'Server-Migration-Inventory'
}
if ($IncludeFileHashes) {
    $IncludeFileInventory = $true
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$inventoryFolder = Join-Path -Path $OutputRoot -ChildPath "$env:COMPUTERNAME-$timestamp"
if (-not $PSCmdlet.ShouldProcess($inventoryFolder, 'Create Windows Server migration inventory folder and reports')) {
    return
}
New-Item -Path $inventoryFolder -ItemType Directory -Force | Out-Null

Write-Verbose "Inventory output: $inventoryFolder"

# Privilege state is evidence because non-elevated runs have predictable gaps.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdministrator) {
    Add-CollectionWarning -Message 'PowerShell is not elevated. Firewall, IIS, certificate, event, SQL, and ACL results may be incomplete. Rerun as Administrator for migration evidence.'
}

# Core platform inventory.
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
$operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
$bios = Get-CimInstance -ClassName Win32_BIOS
$processors = @(Get-CimInstance -ClassName Win32_Processor)
$volumes = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    [pscustomobject]@{
        Drive       = $_.DeviceID
        Label       = $_.VolumeName
        FileSystem  = $_.FileSystem
        SizeGB      = [math]::Round($_.Size / 1GB, 2)
        FreeGB      = [math]::Round($_.FreeSpace / 1GB, 2)
        PercentFree = if ($_.Size) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
    }
})
$networkAdapters = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' | ForEach-Object {
    [pscustomobject]@{
        Description    = $_.Description
        MacAddress     = $_.MACAddress
        DhcpEnabled    = $_.DHCPEnabled
        IPAddress      = ConvertTo-SafeText -Value $_.IPAddress
        Subnet         = ConvertTo-SafeText -Value $_.IPSubnet
        DefaultGateway = ConvertTo-SafeText -Value $_.DefaultIPGateway
        DnsServers     = ConvertTo-SafeText -Value $_.DNSServerSearchOrder
        DnsSuffix      = $_.DNSDomain
    }
})
$shares = @(Get-CimInstance -ClassName Win32_Share -ErrorAction SilentlyContinue | Select-Object Name, Path, Description, Type, MaximumAllowed)
$localUsers = @(Get-CimInstance -ClassName Win32_UserAccount -Filter 'LocalAccount=True' -ErrorAction SilentlyContinue | Select-Object Name, Disabled, Lockout, PasswordExpires, PasswordRequired, SID)
$localGroups = @(Get-LocalGroup -ErrorAction SilentlyContinue | ForEach-Object {
    $group = $_
    $members = @(Get-LocalGroupMember -Group $group.Name -ErrorAction SilentlyContinue)
    foreach ($member in $members) {
        [pscustomobject]@{
            GroupName   = $group.Name
            MemberName  = $member.Name
            ObjectClass = $member.ObjectClass
            PrincipalSource = $member.PrincipalSource
        }
    }
})
$pendingReboot = Get-PendingRebootState
$hotfixes = @(Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object HotFixID, Description, InstalledBy, InstalledOn)

# Application and configuration inventory.
Write-Verbose 'Collecting installed software, features, services, tasks, firewall, and listeners.'
$installedSoftware = @(Get-RegistryInstalledSoftware)
$windowsFeatures = @(Get-WindowsFeatureInventory)
$services = @(Get-CimInstance -ClassName Win32_Service | Select-Object Name, DisplayName, State, StartMode, StartName, PathName, Description, ServiceType)
$scheduledTasks = @(Get-ScheduledTaskInventory)
$firewallRules = @(Get-FirewallInventory)
$listeningEndpoints = @(Get-ListeningEndpointInventory)
$certificates = @(Get-CertificateInventory)
$odbc = @(Get-OdbcInventory)
$iis = Get-IisInventory

# SQL queries and events are skipped only for the explicit quick validation mode.
$sql = if ($Quick) {
    Add-CollectionWarning -Message 'Quick mode skipped SQL metadata queries.'
    [ordered]@{ Instances = @(); Databases = @(); DatabaseFiles = @(); BackupHistory = @(); AgentJobs = @(); DatabaseTriggers = @(); AresPathSettings = @() }
}
else {
    Get-SqlInstanceInventory -TargetDatabasePattern $DatabaseNamePattern -Profile $ApplicationProfile -AdditionalServerInstance $SqlServerInstance
}

$recentEvents = if ($Quick) {
    Add-CollectionWarning -Message 'Quick mode skipped recent event-log collection.'
    @()
}
else {
    @(Get-RecentServerEventInventory -LookbackDays $EventLookbackDays)
}

# Discover migration roots from the selected profile, custom input, installed application
# metadata, IIS, SQL database files, and safe profile-specific customization paths.
$candidateRoots = [System.Collections.Generic.List[string]]::new()
foreach ($applicationPath in $effectiveApplicationRoots) {
    $expandedPath = [Environment]::ExpandEnvironmentVariables($applicationPath)
    if ($expandedPath -and (Test-Path -LiteralPath $expandedPath) -and -not $candidateRoots.Contains($expandedPath)) {
        $candidateRoots.Add($expandedPath)
    }
}
if ($applicationMatchPattern) {
    foreach ($application in @($installedSoftware | Where-Object DisplayName -match $applicationMatchPattern)) {
        $installLocation = [Environment]::ExpandEnvironmentVariables([string]$application.InstallLocation)
        if ($installLocation -and (Test-Path -LiteralPath $installLocation) -and -not $candidateRoots.Contains($installLocation)) {
            $candidateRoots.Add($installLocation)
        }
    }
    foreach ($service in @($services | Where-Object { $_.Name -match $applicationMatchPattern -or $_.DisplayName -match $applicationMatchPattern -or $_.PathName -match $applicationMatchPattern })) {
        $executablePath = if ($service.PathName -match '^"([^"]+)"') { $Matches[1] } elseif ($service.PathName -match '^([^\s]+\.exe)') { $Matches[1] } else { '' }
        $serviceRoot = if ($executablePath) { Split-Path -Path $executablePath -Parent } else { '' }
        if ($serviceRoot -and (Test-Path -LiteralPath $serviceRoot) -and -not $candidateRoots.Contains($serviceRoot)) {
            $candidateRoots.Add($serviceRoot)
        }
    }
}
foreach ($root in @($iis.ContentRoots)) {
    if ($root -and -not $candidateRoots.Contains($root)) { $candidateRoots.Add($root) }
}
foreach ($databaseFile in @($sql.DatabaseFiles)) {
    if ($databaseFile.PhysicalPath) {
        $parent = Split-Path -Path ([string]$databaseFile.PhysicalPath) -Parent
        if ($parent -and (Test-Path -LiteralPath $parent) -and -not $candidateRoots.Contains($parent)) { $candidateRoots.Add($parent) }
    }
}
foreach ($setting in @($sql.AresPathSettings)) {
    $pathValue = [Environment]::ExpandEnvironmentVariables([string]$setting.CustValue)
    if ($pathValue -match '^[A-Za-z]:\\' -and (Test-Path -LiteralPath $pathValue) -and -not $candidateRoots.Contains($pathValue)) {
        $candidateRoots.Add($pathValue)
    }
}

$folderInventory = if ($Quick) {
    Add-CollectionWarning -Message 'Quick mode skipped recursive migration-root sizing and individual file inventory.'
    [ordered]@{ Summary = @(); Files = @(); Truncated = $false }
}
elseif ($candidateRoots.Count -eq 0) {
    Add-CollectionWarning -Message 'No existing application, IIS, or SQL data path was discovered for recursive sizing. Supply -ApplicationRoot for non-standard application/data locations.'
    [ordered]@{ Summary = @(); Files = @(); Truncated = $false }
}
else {
    Get-FolderMigrationInventory -Roots @($candidateRoots) -IncludeFiles:$IncludeFileInventory -IncludeHashes:$IncludeFileHashes -MaximumFileRecords $MaxFileRecords
}
$aclPaths = @(@($candidateRoots) + @($profileDefinition.AclPaths) |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
    Sort-Object -Unique)
$aclInventory = if ($aclPaths.Count -gt 0) { @(Get-PathAclInventory -Paths $aclPaths) } else { @() }

# Compare profile-documented ports with local evidence. This is not a reachability test.
$documentedPorts = if ($ApplicationProfile -eq 'Ares') { @(
    [pscustomobject]@{ Purpose = 'Public web HTTPS (recommended)'; Protocol = 'TCP'; Port = '443'; Direction = 'Inbound'; Requirement = 'Required when serving secure Ares web pages' },
    [pscustomobject]@{ Purpose = 'Public web HTTP'; Protocol = 'TCP'; Port = '80'; Direction = 'Inbound'; Requirement = 'Alternative/redirect; prefer HTTPS' },
    [pscustomobject]@{ Purpose = 'SQL Server'; Protocol = 'TCP'; Port = '1433'; Direction = 'To SQL server'; Requirement = 'Required unless SQL uses another port' },
    [pscustomobject]@{ Purpose = 'SMTP'; Protocol = 'TCP'; Port = '25'; Direction = 'Outbound'; Requirement = 'Default mail relay port; verify local configuration' },
    [pscustomobject]@{ Purpose = 'Ares AutoUpdater FTP'; Protocol = 'TCP'; Port = '20,21'; Direction = 'Outbound'; Requirement = 'Vendor lists for update.atlas-sys.com; confirm whether still used' },
    [pscustomobject]@{ Purpose = 'LDAP/LDAPS'; Protocol = 'TCP'; Port = '389,636'; Direction = 'Outbound'; Requirement = 'Optional when LDAP authentication is configured; prefer LDAPS' },
    [pscustomobject]@{ Purpose = 'Z39.50'; Protocol = 'TCP'; Port = 'Varies'; Direction = 'Outbound'; Requirement = 'Optional; verify OPAC configuration' },
    [pscustomobject]@{ Purpose = 'PatronAPI'; Protocol = 'TCP'; Port = '4500'; Direction = 'Outbound'; Requirement = 'Optional; site-specific' },
    [pscustomobject]@{ Purpose = 'Remote Desktop'; Protocol = 'TCP'; Port = '3389'; Direction = 'Inbound'; Requirement = 'Administrative only; restrict to VPN/management ranges' }
) } else { @() }
$applicationPortReview = foreach ($documentedPort in $documentedPorts) {
    $ports = @($documentedPort.Port -split ',' | Where-Object { $_ -match '^\d+$' })
    $listeners = @($listeningEndpoints | Where-Object { [string]$_.LocalPort -in $ports })
    $rules = @($firewallRules | Where-Object {
        $rulePorts = @(([string]$_.LocalPort) -split ',' | ForEach-Object Trim)
        ($rulePorts | Where-Object { $_ -in $ports }).Count -gt 0
    })
    [pscustomobject]@{
        Purpose          = $documentedPort.Purpose
        Protocol         = $documentedPort.Protocol
        Port             = $documentedPort.Port
        Direction        = $documentedPort.Direction
        Requirement      = $documentedPort.Requirement
        LocalListeners   = ConvertTo-SafeText -Value @($listeners | ForEach-Object { "$($_.Protocol) $($_.LocalAddress):$($_.LocalPort) [$($_.ProcessName)]" })
        MatchingRuleCount = $rules.Count
        MatchingRules    = ConvertTo-SafeText -Value @($rules.DisplayName)
        ReviewStatus     = 'Manual validation required (host evidence does not include AWS SG/NACL or upstream firewalls)'
    }
}

# Hash a few high-value configuration artifacts without copying their contents.
$configurationFiles = [System.Collections.Generic.List[object]]::new()
if (-not $Quick) {
    foreach ($root in @($candidateRoots)) {
        foreach ($file in (Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq 'web.config' -or $_.Extension -in '.dbc', '.config', '.json', '.xml', '.ini' } |
            Select-Object -First 5000)) {
            $hash = try { (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash } catch { '' }
            $configurationFiles.Add([pscustomobject]@{
                FullName         = $file.FullName
                Length           = $file.Length
                LastWriteTimeUtc = $file.LastWriteTimeUtc
                SHA256           = $hash
                ContentExported  = $false
            })
        }
    }

    $systemConfigurationFiles = @(
        "$env:windir\System32\inetsrv\config\applicationHost.config",
        "$env:windir\System32\drivers\etc\hosts",
        "$env:windir\Microsoft.NET\Framework64\v4.0.30319\Config\machine.config"
    )
    foreach ($systemConfigurationFile in $systemConfigurationFiles) {
        if (-not (Test-Path -LiteralPath $systemConfigurationFile -PathType Leaf)) {
            continue
        }
        $file = Get-Item -LiteralPath $systemConfigurationFile
        $hash = try { (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash } catch { '' }
        $configurationFiles.Add([pscustomobject]@{
            FullName         = $file.FullName
            Length           = $file.Length
            LastWriteTimeUtc = $file.LastWriteTimeUtc
            SHA256           = $hash
            ContentExported  = $false
        })
    }
}

# Export detailed evidence.
$csvExports = [ordered]@{
    'InstalledSoftware.csv'   = $installedSoftware
    'WindowsFeatures.csv'     = $windowsFeatures
    'Services.csv'            = $services
    'ScheduledTasks.csv'      = $scheduledTasks
    'FirewallRules.csv'       = $firewallRules
    'ListeningEndpoints.csv'  = $listeningEndpoints
    'ApplicationPortReview.csv' = $applicationPortReview
    'IISSites.csv'            = $iis.Sites
    'IISApplications.csv'     = $iis.Applications
    'IISVirtualDirectories.csv' = $iis.VirtualDirectories
    'IISApplicationPools.csv' = $iis.ApplicationPools
    'IISBindings.csv'         = $iis.Bindings
    'IISAuthentication.csv'   = $iis.Authentication
    'Certificates.csv'        = $certificates
    'ODBC-SystemDSNs.csv'     = $odbc
    'SQL-Instances.csv'       = $sql.Instances
    'SQL-Databases.csv'       = $sql.Databases
    'SQL-DatabaseFiles.csv'   = $sql.DatabaseFiles
    'SQL-BackupHistory.csv'   = $sql.BackupHistory
    'SQL-AgentJobs.csv'       = $sql.AgentJobs
    'SQL-DatabaseTriggers.csv' = $sql.DatabaseTriggers
    'SQL-AresPathSettings.csv' = $sql.AresPathSettings
    'MigrationRoots.csv'      = $folderInventory.Summary
    'MigrationFileInventory.csv' = $folderInventory.Files
    'ConfigurationFileHashes.csv' = @($configurationFiles)
    'PathPermissions.csv'     = $aclInventory
    'Volumes.csv'             = $volumes
    'NetworkAdapters.csv'     = $networkAdapters
    'Shares.csv'              = $shares
    'LocalUsers.csv'          = $localUsers
    'LocalGroupMembers.csv'   = $localGroups
    'InstalledHotfixes.csv'   = $hotfixes
    'RecentWarningErrorEvents.csv' = $recentEvents
}
foreach ($fileName in $csvExports.Keys) {
    Export-InventoryCsv -Data @($csvExports[$fileName]) -Path (Join-Path $inventoryFolder $fileName) -Confirm:$false
}

$inventoryObject = [ordered]@{
    Metadata = [ordered]@{
        ToolVersion          = $script:version
        Author               = $script:author
        CollectedAtLocal     = $script:runDate.ToString('o')
        CollectedAtUtc       = $script:runDate.ToUniversalTime().ToString('o')
        ComputerName         = $env:COMPUTERNAME
        RunAs                = $identity.Name
        Elevated             = $isAdministrator
        QuickMode            = [bool]$Quick
        ApplicationProfile   = $ApplicationProfile
        ApplicationName      = $ApplicationName
        DatabaseNamePattern  = $DatabaseNamePattern
        SqlServerInstance    = @($SqlServerInstance)
        RequestedRoots       = @($ApplicationRoot)
        IncludeFileInventory = [bool]$IncludeFileInventory
        IncludeFileHashes    = [bool]$IncludeFileHashes
    }
    ComputerSystem       = $computerSystem | Select-Object Manufacturer, Model, Domain, DomainRole, TotalPhysicalMemory, NumberOfLogicalProcessors
    OperatingSystem      = $operatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime, WindowsDirectory, SystemDrive
    Bios                 = $bios | Select-Object Manufacturer, SMBIOSBIOSVersion, SerialNumber, ReleaseDate
    Processors           = $processors | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
    PendingReboot        = $pendingReboot
    Volumes              = $volumes
    NetworkAdapters      = $networkAdapters
    InstalledSoftware   = $installedSoftware
    WindowsFeatures     = $windowsFeatures
    Services            = $services
    ScheduledTasks      = $scheduledTasks
    FirewallRules       = $firewallRules
    ListeningEndpoints  = $listeningEndpoints
    ApplicationPortReview = $applicationPortReview
    IIS                 = $iis
    Certificates        = $certificates
    OdbcSystemDsns      = $odbc
    SQL                 = $sql
    MigrationRoots      = $folderInventory.Summary
    ConfigurationFiles  = @($configurationFiles)
    PathPermissions     = $aclInventory
    Shares              = $shares
    LocalUsers          = $localUsers
    LocalGroupMembers   = $localGroups
    InstalledHotfixes   = $hotfixes
    RecentEvents        = $recentEvents
    CollectionWarnings  = @($script:collectionWarnings)
}
$jsonPath = Join-Path $inventoryFolder 'Inventory.json'
$inventoryObject | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8

# Build an Obsidian-compatible report focused on migration decisions.
$profileSoftware = if ($ApplicationProfile -eq 'Ares') {
    @($installedSoftware | Where-Object { $_.DisplayName -match "$applicationMatchPattern|Microsoft SQL Server|Internet Information Services" })
}
elseif ($applicationMatchPattern) {
    @($installedSoftware | Where-Object DisplayName -match $applicationMatchPattern)
}
else {
    @($installedSoftware)
}
$profileServices = if ($applicationMatchPattern) {
    @($services | Where-Object {
        $_.Name -match $applicationMatchPattern -or
        $_.DisplayName -match $applicationMatchPattern -or
        $_.PathName -match $applicationMatchPattern
    })
}
else {
    @()
}
$sqlServices = @($services | Where-Object { $_.Name -match '^(MSSQL|SQLAgent|SQLBrowser)' })
$securitySoftware = @($installedSoftware | Where-Object { $_.DisplayName -match '(?i)CrowdStrike|Falcon|Rapid7|Insight|Defender|Qualys|Tenable|Splunk|Amazon SSM|AWS Systems Manager' })
$updateEvents = @($recentEvents | Where-Object { $_.Provider -match '(?i)WindowsUpdate|Servicing|TrustedInstaller|CBS' })
$lastHotfix = $hotfixes | Select-Object -First 1
$reportTitle = if ($ApplicationProfile -eq 'Ares') { 'Ares Course Reserves Server Migration Inventory' } else { "$ApplicationName Migration Inventory" }

$report = [System.Collections.Generic.List[string]]::new()
$report.Add("# $reportTitle")
$report.Add('')
$report.Add("> [!warning] Sensitive operational evidence")
$report.Add('> This report contains hostnames, IP addresses, service accounts, paths, firewall policy, and certificate metadata. Store it in an access-controlled location. Password/token-like values were redacted, and no file contents, database rows, or private keys were exported.')
$report.Add('')
$report.Add('## Executive snapshot')
$report.Add('')
$report.Add('| Item | Observed value |')
$report.Add('|---|---|')
$report.Add("| Server | $(ConvertTo-MarkdownCell $env:COMPUTERNAME) |")
$report.Add("| Domain | $(ConvertTo-MarkdownCell $computerSystem.Domain) |")
$report.Add("| OS | $(ConvertTo-MarkdownCell "$($operatingSystem.Caption) $($operatingSystem.Version), build $($operatingSystem.BuildNumber), $($operatingSystem.OSArchitecture)") |")
$report.Add("| Last boot | $(ConvertTo-MarkdownCell $operatingSystem.LastBootUpTime) |")
$report.Add("| Pending reboot detected | $(ConvertTo-MarkdownCell $pendingReboot.PendingReboot) |")
$report.Add("| Latest recorded hotfix | $(ConvertTo-MarkdownCell "$($lastHotfix.HotFixID) installed $($lastHotfix.InstalledOn)") |")
$report.Add("| Hardware | $(ConvertTo-MarkdownCell "$($computerSystem.Manufacturer) $($computerSystem.Model); $([math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 1)) GB RAM; $($computerSystem.NumberOfLogicalProcessors) logical CPUs") |")
$report.Add("| Elevated collection | $(ConvertTo-MarkdownCell $isAdministrator) |")
$report.Add("| Application profile | $(ConvertTo-MarkdownCell $ApplicationProfile) |")
$report.Add("| Workload name | $(ConvertTo-MarkdownCell $ApplicationName) |")
$report.Add("| Profile-matched services | $($profileServices.Count) |")
$report.Add("| Total installed applications | $($installedSoftware.Count) |")
$report.Add("| Total services | $($services.Count) |")
$report.Add("| Local SQL instances queried/discovered | $(@($sql.Instances).Count) |")
$report.Add("| IIS sites | $(@($iis.Sites).Count) |")
$report.Add("| Migration roots | $(@($candidateRoots).Count) |")
$report.Add("| Evidence folder | $(ConvertTo-MarkdownCell $inventoryFolder) |")
$report.Add('')
$report.Add('## Migration priorities')
$report.Add('')
$report.Add('1. **Application data:** Identify authoritative databases, application/data roots, shares, configuration files, certificates, and secrets. Back up each through its supported application-aware method and prove the restore before cutover.')
$report.Add('2. **Files and permissions:** Securely copy required application and data paths, then deliberately recreate ACLs for service identities, application-pool identities, operators, and users. Do not blindly reproduce obsolete broad permissions.')
$report.Add('3. **IIS and TLS:** Recreate sites, applications, virtual directories, pools, bindings, authentication settings, and required IIS role services. Reissue or securely transfer the TLS certificate through the approved certificate process; this inventory does not export private keys.')
$report.Add('4. **Services and automation:** Recreate application services, service-account rights, scheduled tasks, and database jobs. Prevent old and new automation from writing to the same production data during cutover.')
$report.Add('5. **Network:** Validate local firewall policy plus AWS Security Groups/NACLs, DNS, load balancer/health checks (if any), SMTP relay allow-listing, and client-to-SQL paths. Host inventory alone cannot prove end-to-end reachability.')
$report.Add('6. **Security agents:** Install and validate CrowdStrike, Rapid7, SSM, logging, backup, and monitoring agents on the replacement. Expect first scans, changed executable paths, and new server identity to create detections or coverage gaps until consoles are verified.')
$report.Add('')
if ($ApplicationProfile -eq 'Ares') {
    $report.Add('### Ares profile notes')
    $report.Add('')
    $report.Add('- Atlas documents `C:\Ares` as the default application root, `C:\AresData` as the default SQL data/backup root, `C:\Ares\Web\WebPages` for web templates, and `C:\Ares\AresDocs` for electronic documents. The inventory also checks IIS-discovered and customization-discovered paths.')
    $report.Add('- Review ACLs on `PublicDocs` and `TempUpload` separately. Atlas documents read/write requirements for the anonymous web identity and staff/FTP identities according to the upload method.')
    $report.Add('- Use a native full SQL backup and restore for the Ares database. Do not copy live MDF/LDF files. Install the matching Ares version first and coordinate installer access/support with Atlas.')
    $report.Add('- Prevent old and new Ares services, SQL Agent jobs, cleanup processes, and add-ons from operating concurrently against production data.')
    $report.Add('')
}
$report.Add("## $ApplicationName and installed applications")
$report.Add('')
if ($profileSoftware.Count -gt 0) {
    $report.Add('| Application | Version | Publisher | Install location |')
    $report.Add('|---|---|---|---|')
    foreach ($app in ($profileSoftware | Select-Object -First 40)) {
        $report.Add("| $(ConvertTo-MarkdownCell $app.DisplayName) | $(ConvertTo-MarkdownCell $app.DisplayVersion) | $(ConvertTo-MarkdownCell $app.Publisher) | $(ConvertTo-MarkdownCell $app.InstallLocation) |")
    }
}
else {
    $report.Add('_No installed-software entry matched the selected application name/profile. Review `InstalledSoftware.csv`, service paths, and portable applications manually._')
}
$report.Add('')
$report.Add('### Profile-matched services')
$report.Add('')
if ($profileServices.Count -gt 0) {
    $report.Add('| Service | State | Start mode | Logon identity | Executable/configuration |')
    $report.Add('|---|---|---|---|---|')
    foreach ($service in $profileServices) {
        $report.Add("| $(ConvertTo-MarkdownCell $service.DisplayName) | $(ConvertTo-MarkdownCell $service.State) | $(ConvertTo-MarkdownCell $service.StartMode) | $(ConvertTo-MarkdownCell $service.StartName) | $(ConvertTo-MarkdownCell $service.PathName) |")
    }
}
else {
    $report.Add('_No service matched the selected application name/profile. This is expected for the General profile; review `Services.csv` for the complete inventory._')
}
$report.Add('')
$report.Add('### SQL services')
$report.Add('')
if ($sqlServices.Count -gt 0) {
    $report.Add('| Service | State | Start mode | Logon identity |')
    $report.Add('|---|---|---|---|')
    foreach ($service in $sqlServices) {
        $report.Add("| $(ConvertTo-MarkdownCell $service.DisplayName) | $(ConvertTo-MarkdownCell $service.State) | $(ConvertTo-MarkdownCell $service.StartMode) | $(ConvertTo-MarkdownCell $service.StartName) |")
    }
}
else {
    $report.Add('_No local SQL Database Engine/Agent/Browser service was found. The database may be remote._')
}
$report.Add('')
$report.Add('## SQL Server and backup evidence')
$report.Add('')
if (@($sql.Databases).Count -gt 0) {
    $report.Add('| Database | State | Recovery | Compatibility | Allocated MB |')
    $report.Add('|---|---|---|---|---|')
    foreach ($database in $sql.Databases) {
        $report.Add("| $(ConvertTo-MarkdownCell $database.DatabaseName) | $(ConvertTo-MarkdownCell $database.State) | $(ConvertTo-MarkdownCell $database.RecoveryModel) | $(ConvertTo-MarkdownCell $database.CompatibilityLevel) | $(ConvertTo-MarkdownCell $database.AllocatedMB) |")
    }
}
else {
    $report.Add('_No database metadata was returned. See collection warnings. This does not mean no database exists._')
}
$report.Add('')
$report.Add("- SQL database file paths: see `SQL-DatabaseFiles.csv`.")
$report.Add("- Latest full/differential/log backup history: see `SQL-BackupHistory.csv`.")
$report.Add("- SQL Agent job history: see `SQL-AgentJobs.csv`.")
$report.Add("- Database triggers for selected non-system/application databases: see `SQL-DatabaseTriggers.csv`; review site/vendor customizations with the DBA.")
if ($ApplicationProfile -eq 'Ares') {
    $report.Add("- Safe Ares path/URL/server customization values: see `SQL-AresPathSettings.csv`. Other customization values require controlled review in Ares Customization Manager.")
}
$report.Add('')
$report.Add('> [!danger] Database backup is not included')
$report.Add('> This discovery run does not create or validate a SQL backup. Before migration, perform a native full backup, copy it off-host, restore it into a test SQL instance, and run application-level validation. A backup that has not been restored is not yet proven.')
$report.Add('')
$report.Add('## IIS, web content, and certificates')
$report.Add('')
if (@($iis.Sites).Count -gt 0) {
    $report.Add('| Site | State | Physical path | Bindings |')
    $report.Add('|---|---|---|---|')
    foreach ($site in $iis.Sites) {
        $report.Add("| $(ConvertTo-MarkdownCell $site.Name) | $(ConvertTo-MarkdownCell $site.State) | $(ConvertTo-MarkdownCell $site.PhysicalPath) | $(ConvertTo-MarkdownCell $site.Bindings) |")
    }
}
else {
    $report.Add('_No IIS site metadata was returned. Review the warnings and confirm that IIS is installed._')
}
$report.Add('')
$report.Add('- Full IIS application, virtual-directory, application-pool, and binding metadata is in the corresponding `IIS*.csv` files.')
$report.Add('- `ConfigurationFileHashes.csv` inventories important config/DBC files by path, date, size, and SHA-256 but deliberately does not copy their contents.')
$report.Add('- `Certificates.csv` records certificate identity and expiry. It does not export private keys. Confirm the approved InCommon/Sectigo replacement process and include the required `USERTrust RSA` intermediate.')
$report.Add('')
$report.Add('## Network and firewall review')
$report.Add('')
if (@($applicationPortReview).Count -gt 0) {
    $report.Add('| Purpose | Port | Direction | Listener evidence | Matching specific-port host rules |')
    $report.Add('|---|---|---|---|---|')
    foreach ($portReview in $applicationPortReview) {
        $report.Add("| $(ConvertTo-MarkdownCell $portReview.Purpose) | $(ConvertTo-MarkdownCell $portReview.Port) | $(ConvertTo-MarkdownCell $portReview.Direction) | $(ConvertTo-MarkdownCell $portReview.LocalListeners) | $(ConvertTo-MarkdownCell $portReview.MatchingRuleCount) |")
    }
    $report.Add('')
    $report.Add('The profile rule count includes enabled rules that explicitly name the listed local port; broad `Any`-port rules are excluded from this summary but remain in `FirewallRules.csv`.')
}
else {
    $report.Add('_The General profile does not assume which application ports are required. Use `ListeningEndpoints.csv` and `FirewallRules.csv`, then validate each flow against the application/vendor architecture._')
}
$report.Add('')
$report.Add('Matching a Windows Firewall rule is only a clue: verify rule direction, profiles, remote-address scope, effective policy, AWS Security Groups/NACLs, campus firewalls, and actual connections. Keep RDP limited to the VPN/approved management ranges. Prefer encrypted protocols and do not open optional vendor ports unless the approved design requires them.')
$report.Add('')
$report.Add('## Storage and migration roots')
$report.Add('')
$report.Add('| Drive | Size GB | Free GB | Percent free |')
$report.Add('|---|---|---|---|')
foreach ($volume in $volumes) {
    $report.Add("| $(ConvertTo-MarkdownCell $volume.Drive) | $(ConvertTo-MarkdownCell $volume.SizeGB) | $(ConvertTo-MarkdownCell $volume.FreeGB) | $(ConvertTo-MarkdownCell $volume.PercentFree) |")
}
$report.Add('')
if (@($folderInventory.Summary).Count -gt 0) {
    $report.Add('| Root | Files | Size GB | Latest write UTC |')
    $report.Add('|---|---|---|---|')
    foreach ($rootSummary in $folderInventory.Summary) {
        $report.Add("| $(ConvertTo-MarkdownCell $rootSummary.Root) | $(ConvertTo-MarkdownCell $rootSummary.FileCount) | $(ConvertTo-MarkdownCell $rootSummary.TotalSizeGB) | $(ConvertTo-MarkdownCell $rootSummary.LatestWriteUtc) |")
    }
}
else {
    $report.Add('_Recursive root sizing was skipped or no candidate roots were found._')
}
$report.Add('')
$report.Add('- `PathPermissions.csv` records top-level ACLs that must be intentionally recreated and then least-privilege reviewed.')
$report.Add('- If requested, `MigrationFileInventory.csv` contains individual file metadata. It is not a copy of the files.')
$report.Add('- File counts and timestamps may change while the application is live. Perform a final delta copy during the controlled cutover window.')
$report.Add('')
$report.Add('## OS update evidence')
$report.Add('')
$report.Add("- Pending reboot: **$($pendingReboot.PendingReboot)** (CBS: $($pendingReboot.ComponentBasedServicing); Windows Update: $($pendingReboot.WindowsUpdate); pending file rename: $($pendingReboot.PendingFileRename); computer rename: $($pendingReboot.ComputerRename)).")
$report.Add("- Warning/error events collected from the last $EventLookbackDays days: **$($recentEvents.Count)** total; **$($updateEvents.Count)** matched Windows Update/servicing providers.")
$report.Add('- Use `RecentWarningErrorEvents.csv` to identify the update failure code and servicing phase before deciding the existing server is unrecoverable. This inventory intentionally does not run DISM repair, SFC, reset update components, or install updates.')
$report.Add('')
$report.Add('## Security and management tooling')
$report.Add('')
if ($securitySoftware.Count -gt 0) {
    foreach ($app in $securitySoftware) {
        $report.Add("- $($app.DisplayName) $($app.DisplayVersion)")
    }
}
else {
    $report.Add('- No expected security/management product matched the installed-software names. Review services and the management consoles; agents can be present without a conventional uninstall entry.')
}
$report.Add('')
$report.Add('Do not clone endpoint-security agent identities or certificates from the old server. Install/register fresh agents on the replacement, confirm the new asset appears in CrowdStrike and Rapid7, and retire the old asset record after cutover.')
$report.Add('')
$report.Add('## Manual items the server cannot discover')
$report.Add('')
$report.Add('- Vendor support entitlement, installer/media access, licenses, supported application/OS/database combinations, and whether the vendor must perform or validate the migration.')
$report.Add('- AWS EC2 instance profile, AMI/build pipeline, subnet, Security Groups, NACLs, Elastic IPs, Route 53 records, load balancers, target groups, EBS encryption/KMS key, snapshots, SSM associations, CloudWatch alarms, and backup policy.')
$report.Add('- External DNS names, cutover/rollback TTL, production/test subnet placement, private IP connection strings, and upstream allow-lists.')
$report.Add('- SMTP relay source-IP allow-listing, sender addresses, and mail-flow tests.')
$report.Add('- Service-account passwords/managed-account design, SQL authentication secrets, certificate private keys, vendor license data, and any secrets stored outside approved secret management.')
$report.Add('- Application-level integrations such as identity/authentication, APIs, middleware, scheduled imports/exports, network shares, mail, printing, monitoring, and downstream reporting/ODBC clients.')
if ($ApplicationProfile -eq 'Ares') {
    $report.Add('- Ares-specific integrations: LDAP/LDAPS, LTI/LMS, Z39.50, PatronAPI, SSO, add-ons, document delivery, print/email templates, and client database aliases.')
    $report.Add('- Ares `dbo.Customization` values outside the path/URL/server allow-list. Review them in Ares Customization Manager; do not broadly export the table into this evidence bundle because it may contain secrets.')
}
$report.Add('')
$report.Add('## Recommended cutover gates')
$report.Add('')
$report.Add('- [ ] The application vendor/owner confirms the target platform, matching application version, migration method, and support window.')
$report.Add('- [ ] New server is patched, domain-joined, hardened, monitored, backed up, and has CrowdStrike/Rapid7/SSM coverage.')
$report.Add('- [ ] Required Windows roles, IIS/TLS where applicable, services, paths, permissions, and runtime dependencies match the approved design.')
$report.Add('- [ ] Test restoration of the SQL full backup succeeds; DBCC CHECKDB and application smoke tests pass.')
$report.Add('- [ ] Custom triggers, database users/login mappings, maintenance/backup jobs, and application settings are reviewed.')
$report.Add('- [ ] Pre-copy and final delta-copy plans exist for every file-based application/data root.')
$report.Add('- [ ] Firewall and AWS rules use least privilege; web, database, mail, authentication, and integrations are tested from the real source networks.')
$report.Add('- [ ] Old application services/automation and writable data sources are stopped or isolated before new production services are enabled.')
$report.Add('- [ ] DNS/IP cutover, rollback decision point, outage communication, and owner sign-off are documented.')
$report.Add('- [ ] Post-cutover tests cover every user role, critical workflow, integration, scheduled process, backup, log, and monitor.')
if ($ApplicationProfile -eq 'Ares') {
    $report.Add('- [ ] Ares validation covers patron login, course lookup, staff client, LTI/LMS if used, document upload/delivery, email, add-ons, cleanup, and SQL backups.')
}
$report.Add('')
$report.Add('## Collection warnings and gaps')
$report.Add('')
if ($script:collectionWarnings.Count -gt 0) {
    foreach ($warning in $script:collectionWarnings) {
        $report.Add("- $(ConvertTo-SafeText $warning)")
    }
}
else {
    $report.Add('- No collection warnings were recorded. This does not replace manual validation.')
}
$report.Add('')
$report.Add('## Evidence index')
$report.Add('')
$report.Add('- `Inventory.json` — complete structured snapshot for comparison or automation.')
$report.Add('- `InstalledSoftware.csv`, `WindowsFeatures.csv`, `Services.csv`, `ScheduledTasks.csv` — application/runtime build evidence.')
$report.Add('- `FirewallRules.csv`, `ListeningEndpoints.csv`, optional `ApplicationPortReview.csv`, `NetworkAdapters.csv` — host network evidence.')
$report.Add('- `IIS*.csv`, `Certificates.csv`, `ConfigurationFileHashes.csv` — web and TLS evidence.')
$report.Add('- `SQL-*.csv`, `ODBC-SystemDSNs.csv` — SQL/ODBC metadata (no database row export or passwords).')
$report.Add('- `MigrationRoots.csv`, optional `MigrationFileInventory.csv`, `PathPermissions.csv`, `Shares.csv`, `Volumes.csv` — storage and permissions evidence.')
$report.Add('- `InstalledHotfixes.csv`, `RecentWarningErrorEvents.csv` — patch/update troubleshooting evidence.')
$report.Add('')
$report.Add("Generated by Get-WindowsServerMigrationInventory.ps1 v$($script:version) using the $ApplicationProfile profile on $($script:runDate.ToString('yyyy-MM-dd HH:mm:ss zzz')).")

$reportPath = Join-Path $inventoryFolder 'Windows-Server-Migration-Inventory.md'
$report | Set-Content -LiteralPath $reportPath -Encoding utf8

# Create integrity hashes after all evidence files exist, excluding the manifest itself.
$manifestPath = Join-Path $inventoryFolder 'Evidence-SHA256.csv'
$manifest = @(Get-ChildItem -LiteralPath $inventoryFolder -File | Where-Object FullName -ne $manifestPath | ForEach-Object {
    [pscustomobject]@{
        FileName = $_.Name
        Length   = $_.Length
        SHA256   = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
})
$manifest | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding utf8

$archivePath = $null
if ($CreateArchive) {
    $archivePath = "$inventoryFolder.zip"
    if ($PSCmdlet.ShouldProcess($archivePath, 'Create ZIP archive of migration inventory')) {
        Compress-Archive -LiteralPath $inventoryFolder -DestinationPath $archivePath -CompressionLevel Optimal -Force
    }
}

Write-Output ([pscustomobject]@{
    ReportPath      = $reportPath
    EvidenceFolder = $inventoryFolder
    ArchivePath     = $archivePath
    WarningCount    = $script:collectionWarnings.Count
    Elevated        = $isAdministrator
})
