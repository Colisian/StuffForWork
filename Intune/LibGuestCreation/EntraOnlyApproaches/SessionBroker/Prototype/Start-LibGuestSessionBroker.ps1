#Requires -Version 5.1

<#
.SYNOPSIS
    Runs the LibGuest session broker inside a Shared PC guest session.

.DESCRIPTION
    Evaluates the current interactive identity before loading any UI. The broker
    window opens only when the current account is local, Shared PC configuration is
    present, and the current username matches the configured disposable-account
    pattern. All other sessions exit without displaying a window.

    On a successful sign-in the broker authenticates the SIMS-issued
    libguestN@UMD.EDU credential with CreateProcessWithLogonW and starts an
    allowlisted application under the mapped local security context. Launched
    processes are held in a job object so the whole tree can be terminated
    deterministically at session end.

    The broker account still owns the interactive session, window station, and
    desktop. This produces an application session, not a Windows desktop logon.
    See ../README.md for why that ceiling is inherent to the approach.

    Use -ProbeOnly inside a Shared PC Guest session to collect the session markers
    and launch prerequisites needed to validate deployment.

.PARAMETER ProbeOnly
    Writes the session-context and prerequisite results as JSON and does not
    display the UI. Never authenticates.

.PARAMETER ApplicationId
    Overrides DefaultApplicationId from broker-settings.json. Must name an entry in
    the configured Applications allowlist.

.PARAMETER ForceGuestUi
    Displays the UI without passing the guest-session gate, for UI development on a
    test workstation. Ignored unless AllowDevelopmentOverrides is true in
    broker-settings.json, which ships false so a production package cannot present
    a credential prompt outside the gate.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Start-LibGuestSessionBroker.ps1 -ProbeOnly

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Start-LibGuestSessionBroker.ps1

.NOTES
    Author:  Oji / UMD Libraries
    Date:    2026-07-26
    Version: 0.2.0

    Exit codes: 0 success or gate not passed (both are normal), 1 broker failure.
#>

[CmdletBinding()]
param(
    [switch]$ProbeOnly,
    [string]$ApplicationId,
    [switch]$ForceGuestUi
)

begin {
    $ErrorActionPreference = 'Stop'
}

end {
    #region Logging

    $script:LogDirectory = Join-Path $env:ProgramData 'LibGuestSessionBroker'
    $script:LogPath = Join-Path $script:LogDirectory 'broker.log'

    function Write-BrokerLog {
        <#
        .SYNOPSIS
            Appends a line to the broker log. Never throws and never terminates.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-26
            Version: 0.2.0

            Callers must not pass credential material or, unless LogGuestPrincipal
            is enabled, a guest principal. See the retention note in ../README.md.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateSet('INFO', 'WARN', 'ERROR')]
            [string]$Level,

            [Parameter(Mandatory)]
            [string]$Message
        )

        process {
            try {
                if (-not (Test-Path -LiteralPath $script:LogDirectory)) {
                    New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null
                }
                $line = '{0} {1} [{2}] {3}' -f (Get-Date).ToString('o'), $Level, $PID, $Message
                Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
            }
            catch {
                # Logging is best-effort. A read-only or ACL-restricted log
                # directory must never take the broker down.
            }
        }
    }

    #endregion

    #region Configuration

    function Get-BrokerSettingValue {
        <#
        .SYNOPSIS
            Reads one setting, failing closed when it is absent or the wrong type.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-26
            Version: 0.2.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [psobject]$Configuration,

            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [ValidateSet('Boolean', 'Int32', 'String', 'Array')]
            [string]$Type
        )

        process {
            $property = $Configuration.PSObject.Properties[$Name]
            if ($null -eq $property) {
                throw "Required setting '$Name' is missing from broker-settings.json."
            }

            $value = $property.Value

            switch ($Type) {
                'Boolean' {
                    # Deliberately strict. A gate toggle that arrives as a string
                    # or a null must fail the load, not silently drop the
                    # requirement it controls.
                    if ($value -isnot [bool]) {
                        throw "Setting '$Name' must be a JSON boolean (true or false), not '$value'."
                    }
                    return $value
                }
                'Int32' {
                    $parsed = 0
                    if ($null -eq $value -or -not [int]::TryParse([string]$value, [ref]$parsed)) {
                        throw "Setting '$Name' must be an integer."
                    }
                    return $parsed
                }
                'String' {
                    if ([string]::IsNullOrWhiteSpace($value)) {
                        throw "Setting '$Name' must be a non-empty string."
                    }
                    return [string]$value
                }
                'Array' {
                    $items = @($value)
                    if ($items.Count -eq 0) {
                        throw "Setting '$Name' must contain at least one entry."
                    }
                    return $items
                }
            }
        }
    }

    function Get-BrokerConfiguration {
        <#
        .SYNOPSIS
            Loads broker-settings.json into a validated, normalized settings object.
        .DESCRIPTION
            Every consumer downstream receives already-coerced types. Nothing in
            this script re-parses a raw configuration value.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-26
            Version: 0.2.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        begin {
            $ErrorActionPreference = 'Stop'
        }

        process {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                throw "Broker configuration not found: $Path"
            }

            $configuration = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json

            $pattern = Get-BrokerSettingValue -Configuration $configuration -Name 'BrokerSessionAccountPattern' -Type 'String'

            # The pattern is the one always-required condition, and -match is a
            # substring match unless anchored. An unanchored pattern such as
            # 'shpc' would match any username containing it.
            if (-not ($pattern.StartsWith('^') -and $pattern.EndsWith('$'))) {
                throw "BrokerSessionAccountPattern must be anchored with '^' and '$' so it cannot match a substring. Current value: '$pattern'"
            }
            try {
                [void][regex]::new($pattern)
            }
            catch {
                throw "BrokerSessionAccountPattern is not a valid regular expression: $($_.Exception.Message)"
            }

            $minimumGuestNumber = Get-BrokerSettingValue -Configuration $configuration -Name 'MinimumGuestNumber' -Type 'Int32'
            $maximumGuestNumber = Get-BrokerSettingValue -Configuration $configuration -Name 'MaximumGuestNumber' -Type 'Int32'

            if ($minimumGuestNumber -lt 1 -or $maximumGuestNumber -lt $minimumGuestNumber) {
                throw 'MinimumGuestNumber and MaximumGuestNumber must define a valid range starting at 1 or higher.'
            }

            $sessionTimeoutMinutes = Get-BrokerSettingValue -Configuration $configuration -Name 'SessionTimeoutMinutes' -Type 'Int32'
            if ($sessionTimeoutMinutes -lt 1) {
                throw 'SessionTimeoutMinutes must be 1 or greater.'
            }

            $allowedRoots = @(
                Get-BrokerSettingValue -Configuration $configuration -Name 'AllowedApplicationRoots' -Type 'Array' |
                    ForEach-Object { [Environment]::ExpandEnvironmentVariables([string]$_) } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    ForEach-Object { [System.IO.Path]::GetFullPath($_).TrimEnd('\') }
            )
            if ($allowedRoots.Count -eq 0) {
                throw 'AllowedApplicationRoots did not resolve to any existing path.'
            }

            $applications = @(Get-BrokerSettingValue -Configuration $configuration -Name 'Applications' -Type 'Array')
            foreach ($application in $applications) {
                foreach ($field in @('Id', 'DisplayName', 'Path', 'Mode')) {
                    if ([string]::IsNullOrWhiteSpace($application.$field)) {
                        throw "Every entry in Applications requires a non-empty '$field'."
                    }
                }
                if ($application.Mode -notin @('IdentityTest', 'Session')) {
                    throw "Application '$($application.Id)' has an unsupported Mode '$($application.Mode)'. Use 'IdentityTest' or 'Session'."
                }
            }

            $defaultApplicationId = Get-BrokerSettingValue -Configuration $configuration -Name 'DefaultApplicationId' -Type 'String'
            if ($applications.Id -notcontains $defaultApplicationId) {
                throw "DefaultApplicationId '$defaultApplicationId' does not match any entry in Applications."
            }

            [pscustomobject]@{
                BrokerSessionAccountPattern = $pattern
                RequireLocalAccount         = Get-BrokerSettingValue -Configuration $configuration -Name 'RequireLocalAccount' -Type 'Boolean'
                RequireSharedPcRegistry     = Get-BrokerSettingValue -Configuration $configuration -Name 'RequireSharedPcRegistry' -Type 'Boolean'
                RequireGuestsGroup          = Get-BrokerSettingValue -Configuration $configuration -Name 'RequireGuestsGroup' -Type 'Boolean'
                AllowDevelopmentOverrides   = Get-BrokerSettingValue -Configuration $configuration -Name 'AllowDevelopmentOverrides' -Type 'Boolean'
                LogGuestPrincipal           = Get-BrokerSettingValue -Configuration $configuration -Name 'LogGuestPrincipal' -Type 'Boolean'
                GuestAccountPrefix          = Get-BrokerSettingValue -Configuration $configuration -Name 'GuestAccountPrefix' -Type 'String'
                Realm                       = Get-BrokerSettingValue -Configuration $configuration -Name 'Realm' -Type 'String'
                MinimumGuestNumber          = $minimumGuestNumber
                MaximumGuestNumber          = $maximumGuestNumber
                SessionTimeoutMinutes       = $sessionTimeoutMinutes
                AllowedApplicationRoots     = $allowedRoots
                DefaultApplicationId        = $defaultApplicationId
                Applications                = $applications
            }
        }
    }

    #endregion

    #region Session gate

    function Get-SharedPcSessionContext {
        <#
        .SYNOPSIS
            Returns identity and Shared PC markers for the current session.
        .DESCRIPTION
            Identity facts come from WindowsIdentity and the LocalAccounts module,
            not from USERNAME/USERDOMAIN. Environment variables are writable by the
            user they describe, so they are collected for diagnostics only and are
            never used to decide the gate.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-26
            Version: 0.2.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$BrokerSessionAccountPattern
        )

        begin {
            $ErrorActionPreference = 'Stop'
        }

        process {
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $identityName = $identity.Name
            $currentSid = $identity.User.Value
            $groupSids = @($identity.Groups | ForEach-Object { $_.Value })

            $identityParts = $identityName -split '\\', 2
            if ($identityParts.Count -eq 2) {
                $authority = $identityParts[0]
                $userName = $identityParts[1]
            }
            else {
                $authority = ''
                $userName = $identityName
            }

            # Authoritative local-account test: is this SID a local SAM user?
            # An Entra identity (S-1-12-1-...) and a domain identity are both
            # absent from this list.
            $localAccountSource = 'LocalAccounts'
            try {
                $localSids = @((Get-LocalUser -ErrorAction Stop).SID.Value)
                $isLocalAccount = $localSids -contains $currentSid
            }
            catch {
                $localAccountSource = 'EnvironmentFallback'
                $isLocalAccount = $authority -ieq [Environment]::MachineName
            }

            $sharedPcPaths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedPC',
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedPC\NodeValues',
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedPC\AccountManagement'
            )
            $sharedPcPathsFound = @($sharedPcPaths | Where-Object { Test-Path -LiteralPath $_ })

            [pscustomobject]@{
                SchemaVersion               = 2
                CollectedAt                 = (Get-Date).ToString('o')
                ComputerName                = [Environment]::MachineName
                IdentityName                = $identityName
                UserName                    = $userName
                Authority                   = $authority
                UserSid                     = $currentSid
                IsLocalAccount              = $isLocalAccount
                LocalAccountSource          = $localAccountSource
                MatchesBrokerAccountPattern = $userName -match $BrokerSessionAccountPattern
                IsGuestsGroupMember         = $groupSids -contains 'S-1-5-32-546'
                IsUsersGroupMember          = $groupSids -contains 'S-1-5-32-545'
                IsSharedPcConfigured        = $sharedPcPathsFound.Count -gt 0
                SharedPcRegistryPathsFound  = $sharedPcPathsFound
                EnvironmentUserName         = $env:USERNAME
                EnvironmentUserDomain       = $env:USERDOMAIN
            }
        }
    }

    function Test-SharedPcGuestSession {
        <#
        .SYNOPSIS
            Determines whether the current session should display the broker UI.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-26
            Version: 0.2.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [psobject]$SessionContext,

            [Parameter(Mandatory)]
            [psobject]$Settings
        )

        begin {
            $ErrorActionPreference = 'Stop'
        }

        process {
            $requirements = [ordered]@{
                BrokerSessionAccountPattern = [bool]$SessionContext.MatchesBrokerAccountPattern
            }

            if ($Settings.RequireLocalAccount) {
                $requirements.LocalAccount = [bool]$SessionContext.IsLocalAccount
            }

            if ($Settings.RequireSharedPcRegistry) {
                $requirements.SharedPcConfigured = [bool]$SessionContext.IsSharedPcConfigured
            }

            if ($Settings.RequireGuestsGroup) {
                $requirements.GuestsGroupMember = [bool]$SessionContext.IsGuestsGroupMember
            }

            $failedRequirements = @(
                $requirements.GetEnumerator() |
                    Where-Object { -not $_.Value } |
                    ForEach-Object { $_.Key }
            )

            [pscustomobject]@{
                IsGuestSession     = $failedRequirements.Count -eq 0
                Requirements       = [pscustomobject]$requirements
                FailedRequirements = $failedRequirements
            }
        }
    }

    #endregion

    #region Launch prerequisites

    function Test-BrokerLaunchPrerequisite {
        <#
        .SYNOPSIS
            Checks the environment conditions CreateProcessWithLogonW depends on.
        .DESCRIPTION
            The Secondary Logon service backs CreateProcessWithLogonW. Several
            common hardening baselines disable it, which surfaces as an opaque
            launch failure at the worst possible moment.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-26
            Version: 0.2.0
        #>
        [CmdletBinding()]
        param()

        begin {
            $ErrorActionPreference = 'Stop'
        }

        process {
            $service = Get-Service -Name 'seclogon' -ErrorAction SilentlyContinue
            $startType = if ($service) { [string]$service.StartType } else { 'NotInstalled' }
            $status = if ($service) { [string]$service.Status } else { 'NotInstalled' }

            [pscustomobject]@{
                SecondaryLogonPresent   = $null -ne $service
                SecondaryLogonStartType = $startType
                SecondaryLogonStatus    = $status
                SecondaryLogonUsable    = ($null -ne $service) -and ($startType -ne 'Disabled')
                IsSystemAccount         = [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
            }
        }
    }

    function Resolve-BrokerApplication {
        <#
        .SYNOPSIS
            Resolves an allowlist entry to a validated absolute executable path.
        .DESCRIPTION
            Expands environment variables, canonicalizes the result so a relative
            traversal cannot escape, and confirms the target sits under a
            configured allowed root. Patron input never reaches this function.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-26
            Version: 0.2.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [psobject]$Settings,

            [Parameter(Mandatory)]
            [string]$ApplicationId
        )

        begin {
            $ErrorActionPreference = 'Stop'
        }

        process {
            $application = @($Settings.Applications | Where-Object { $_.Id -eq $ApplicationId })[0]
            if ($null -eq $application) {
                throw "Application '$ApplicationId' is not present in the configured allowlist."
            }

            $expanded = [Environment]::ExpandEnvironmentVariables([string]$application.Path)
            if (-not [System.IO.Path]::IsPathRooted($expanded)) {
                throw "Application '$ApplicationId' must specify an absolute path. Got: '$expanded'"
            }

            # GetFullPath collapses any '..' segments before the root check, so a
            # path such as %SystemRoot%\..\Users\x.exe cannot pass as trusted.
            $fullPath = [System.IO.Path]::GetFullPath($expanded)

            $isUnderAllowedRoot = $false
            foreach ($root in $Settings.AllowedApplicationRoots) {
                if ($fullPath.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
                    $isUnderAllowedRoot = $true
                    break
                }
            }
            if (-not $isUnderAllowedRoot) {
                throw "Application '$ApplicationId' resolves to '$fullPath', which is outside every AllowedApplicationRoots entry."
            }

            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                throw "Application '$ApplicationId' resolves to '$fullPath', which does not exist on this computer."
            }

            [pscustomobject]@{
                Id               = [string]$application.Id
                DisplayName      = [string]$application.DisplayName
                Path             = $fullPath
                Arguments        = [string]$application.Arguments
                Mode             = [string]$application.Mode
                WorkingDirectory = [System.IO.Path]::GetDirectoryName($fullPath)
            }
        }
    }

    function Get-BrokerLogonFailureCategory {
        <#
        .SYNOPSIS
            Classifies a Win32 launch error as a credential or infrastructure fault.
        .DESCRIPTION
            The patron sees one identical message for every credential-related
            code so the dialog never discloses whether an account exists, is
            locked, or is disabled. The specific code goes to the log instead.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-26
            Version: 0.2.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [int]$Win32Error
        )

        process {
            $credentialErrors = @(
                1326, # ERROR_LOGON_FAILURE
                1327, # ERROR_ACCOUNT_RESTRICTION
                1328, # ERROR_INVALID_LOGON_HOURS
                1329, # ERROR_INVALID_WORKSTATION
                1330, # ERROR_PASSWORD_EXPIRED
                1331, # ERROR_ACCOUNT_DISABLED
                1385, # ERROR_LOGON_TYPE_NOT_GRANTED
                1793, # ERROR_ACCOUNT_EXPIRED
                1907, # ERROR_PASSWORD_MUST_CHANGE
                1909, # ERROR_ACCOUNT_LOCKED_OUT
                1938  # ERROR_LOGON_SERVER_CONFLICT
            )

            if ($Win32Error -in $credentialErrors) {
                return 'Credential'
            }
            return 'Infrastructure'
        }
    }

    function Initialize-BrokerNativeLauncher {
        <#
        .SYNOPSIS
            Compiles the CreateProcessWithLogonW wrapper into the session.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-26
            Version: 0.2.0

            Add-Type emits a dynamically compiled assembly. A production WDAC or
            App Control policy will block that; the shipping form of this broker
            is a signed compiled executable, per ../README.md.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$SourcePath
        )

        begin {
            $ErrorActionPreference = 'Stop'
        }

        process {
            if ('UMD.Libraries.LibGuest.BrokerLauncher' -as [type]) {
                return
            }
            if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
                throw "Native launcher source not found: $SourcePath"
            }
            Add-Type -Path $SourcePath
        }
    }

    #endregion

    #region User interface

    function Show-LibGuestBrokerWindow {
        <#
        .SYNOPSIS
            Displays the broker dialog and drives the guest session lifecycle.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-26
            Version: 0.2.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$XamlPath,

            [Parameter(Mandatory)]
            [psobject]$Settings,

            [Parameter(Mandatory)]
            [psobject]$Application,

            [switch]$DevelopmentMode
        )

        begin {
            $ErrorActionPreference = 'Stop'
        }

        process {
            if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
                throw 'The broker UI requires an STA thread. Start PowerShell without -MTA (console defaults are STA).'
            }

            Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

            if (-not (Test-Path -LiteralPath $XamlPath -PathType Leaf)) {
                throw "Broker window definition not found: $XamlPath"
            }

            [xml]$xaml = Get-Content -LiteralPath $XamlPath -Raw -Encoding UTF8
            $xmlReader = New-Object System.Xml.XmlNodeReader $xaml
            try {
                $window = [Windows.Markup.XamlReader]::Load($xmlReader)
            }
            finally {
                $xmlReader.Close()
            }

            $guestNumberTextBox = $window.FindName('GuestNumberTextBox')
            $guestPasswordBox = $window.FindName('GuestPasswordBox')
            $statusTextBlock = $window.FindName('StatusTextBlock')
            $signInButton = $window.FindName('SignInButton')

            # The XAML ships in kiosk presentation. On a development machine that
            # would leave an unclosable fullscreen topmost window on screen, so
            # step it back down to an ordinary dialog.
            if ($DevelopmentMode) {
                $window.WindowState = [System.Windows.WindowState]::Normal
                $window.WindowStyle = [System.Windows.WindowStyle]::SingleBorderWindow
                $window.Topmost = $false
            }

            # Keep the input constraints tied to configuration so the range lives
            # in exactly one place.
            $longestAccepted = '{0}{1}' -f $Settings.GuestAccountPrefix, $Settings.MaximumGuestNumber
            $guestNumberTextBox.MaxLength = $longestAccepted.Length
            $guestNumberTextBox.ToolTip = 'Enter a number from {0} through {1}' -f $Settings.MinimumGuestNumber, $Settings.MaximumGuestNumber

            $errorBrush = '#B00020'
            $infoBrush = '#555555'

            $state = @{
                Timer        = $null
                SessionStart = $null
                Busy         = $false
                AllowClose   = [bool]$DevelopmentMode
            }

            $setStatus = {
                param([string]$Text, [string]$Brush)
                $statusTextBlock.Foreground = $Brush
                $statusTextBlock.Text = $Text
            }.GetNewClosure()

            $resetToSignIn = {
                $state.Busy = $false
                $state.SessionStart = $null
                if ($state.Timer) {
                    $state.Timer.Stop()
                }
                $signInButton.IsEnabled = $true
                $guestNumberTextBox.IsEnabled = $true
                $guestPasswordBox.IsEnabled = $true
                $guestNumberTextBox.Clear()
                $guestPasswordBox.Clear()
                $window.Visibility = [System.Windows.Visibility]::Visible
                # Topmost is deliberately re-asserted: the window returns while
                # the guest application is still tearing down, and its dying
                # windows can otherwise land above the dialog in the z-order.
                $window.Topmost = $false
                $window.Topmost = $true
                $window.Activate() | Out-Null
                $guestNumberTextBox.Focus() | Out-Null
            }.GetNewClosure()

            $endSession = {
                param([string]$Reason)
                [UMD.Libraries.LibGuest.BrokerLauncher]::EndSession()
                Write-BrokerLog -Level 'INFO' -Message "Guest session ended. Reason=$Reason"
                & $resetToSignIn
                & $setStatus 'Session ended. The computer is ready for the next guest.' $infoBrush
            }.GetNewClosure()

            # Polling on a dispatcher timer rather than blocking on the process
            # handle: a blocking wait on the UI thread stops the message pump and
            # Windows marks the broker unresponsive.
            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromSeconds(2)
            $state.Timer = $timer

            $timer.Add_Tick({
                try {
                    if (-not [UMD.Libraries.LibGuest.BrokerLauncher]::SessionIsActive) {
                        & $endSession 'JobClosed'
                        return
                    }
                    if ([UMD.Libraries.LibGuest.BrokerLauncher]::WaitForSessionExit(0)) {
                        & $endSession 'ApplicationExited'
                        return
                    }
                    $elapsed = (Get-Date) - $state.SessionStart
                    if ($elapsed.TotalMinutes -ge $Settings.SessionTimeoutMinutes) {
                        & $endSession 'TimeLimitReached'
                    }
                }
                catch {
                    Write-BrokerLog -Level 'ERROR' -Message "Session monitor fault: $($_.Exception.Message)"
                    & $endSession 'MonitorFault'
                }
            }.GetNewClosure())

            $signInButton.Add_Click({
                # A terminating error inside a WPF event handler unwinds to the
                # dispatcher and takes the window down, which would drop the
                # patron onto the bare broker desktop.
                try {
                    if ($state.Busy) {
                        return
                    }

                    & $setStatus '' $errorBrush

                    $rawGuestNumber = $guestNumberTextBox.Text.Trim()
                    $prefixPattern = '^(?i:{0})' -f [regex]::Escape($Settings.GuestAccountPrefix)
                    $numberText = $rawGuestNumber -replace $prefixPattern, ''
                    $guestNumber = 0

                    if (-not [int]::TryParse($numberText, [ref]$guestNumber) -or
                        $guestNumber -lt $Settings.MinimumGuestNumber -or
                        $guestNumber -gt $Settings.MaximumGuestNumber) {
                        & $setStatus ('Enter a guest number from {0} through {1}.' -f $Settings.MinimumGuestNumber, $Settings.MaximumGuestNumber) $errorBrush
                        $guestNumberTextBox.Focus() | Out-Null
                        return
                    }

                    if ($guestPasswordBox.SecurePassword.Length -eq 0) {
                        & $setStatus 'Enter the password issued by library staff.' $errorBrush
                        $guestPasswordBox.Focus() | Out-Null
                        return
                    }

                    # Rebuilt from the parsed integer, never from raw input.
                    $principal = '{0}{1}@{2}' -f $Settings.GuestAccountPrefix, $guestNumber, $Settings.Realm
                    $loggedPrincipal = if ($Settings.LogGuestPrincipal) { $principal } else { '(redacted)' }

                    $state.Busy = $true
                    $signInButton.IsEnabled = $false
                    $guestNumberTextBox.IsEnabled = $false
                    $guestPasswordBox.IsEnabled = $false
                    & $setStatus 'Signing in...' $infoBrush

                    # Force a repaint before the synchronous logon call, which can
                    # block for seconds while the KDC is contacted.
                    $window.Dispatcher.Invoke([action] {}, [Windows.Threading.DispatcherPriority]::Render)

                    $securePassword = $guestPasswordBox.SecurePassword
                    try {
                        $launchResult = [UMD.Libraries.LibGuest.BrokerLauncher]::StartSession(
                            $principal,
                            $null, # Domain: the UPN carries the realm.
                            $securePassword,
                            $Application.Path,
                            $Application.Arguments,
                            $Application.WorkingDirectory,
                            ($Application.Mode -eq 'Session')
                        )
                    }
                    finally {
                        # PasswordBox.SecurePassword hands back a fresh copy on
                        # every read. Dispose ours; Clear() only handles the
                        # control's own buffer.
                        $securePassword.Dispose()
                        $guestPasswordBox.Clear()
                    }

                    if (-not $launchResult.Succeeded) {
                        $category = Get-BrokerLogonFailureCategory -Win32Error $launchResult.Win32Error
                        Write-BrokerLog -Level 'WARN' -Message (
                            'Launch failed. Principal={0} Application={1} Stage={2} Win32Error={3} Category={4}' -f
                            $loggedPrincipal, $Application.Id, $launchResult.FailureStage, $launchResult.Win32Error, $category
                        )

                        if ($category -eq 'Credential') {
                            # Identical text for every credential fault.
                            & $setStatus 'Sign-in failed. Check the guest number and password, then try again.' $errorBrush
                        }
                        else {
                            & $setStatus 'This computer cannot start a guest session right now. Please visit the library service desk.' $errorBrush
                        }

                        $state.Busy = $false
                        $signInButton.IsEnabled = $true
                        $guestNumberTextBox.IsEnabled = $true
                        $guestPasswordBox.IsEnabled = $true
                        $guestNumberTextBox.Focus() | Out-Null
                        return
                    }

                    Write-BrokerLog -Level 'INFO' -Message (
                        'Launch succeeded. Principal={0} Application={1} Pid={2} TokenAccount={3} TokenSid={4}' -f
                        $loggedPrincipal, $Application.Id, $launchResult.ProcessId, $launchResult.TokenAccount, $launchResult.TokenSid
                    )

                    if ($Application.Mode -eq 'IdentityTest') {
                        # Nothing ran as the guest: the process was created
                        # suspended, inspected, and torn down. The token readback
                        # is the entire result.
                        & $resetToSignIn
                        & $setStatus (
                            'Authentication succeeded. Windows mapped the credential to {0} (SID {1}). No application was started in identity-test mode.' -f
                            $launchResult.TokenAccount, $launchResult.TokenSid
                        ) $infoBrush
                        return
                    }

                    $state.SessionStart = Get-Date
                    $window.Hide()
                    $timer.Start()
                }
                catch {
                    Write-BrokerLog -Level 'ERROR' -Message "Sign-in handler fault: $($_.Exception.Message)"
                    try { [UMD.Libraries.LibGuest.BrokerLauncher]::EndSession() } catch { }
                    & $resetToSignIn
                    & $setStatus 'Something went wrong starting the session. Please visit the library service desk.' $errorBrush
                }
            }.GetNewClosure())

            $window.Add_ContentRendered({
                $guestNumberTextBox.Focus() | Out-Null
            }.GetNewClosure())

            # With WindowStyle="None" there is no close button, but Alt+F4 still
            # closes the window and would drop the patron onto the desktop. Refuse
            # unless the broker itself authorised the close.
            $window.Add_Closing({
                param($eventSender, $eventArgs)
                if (-not $state.AllowClose) {
                    $eventArgs.Cancel = $true
                }
            }.GetNewClosure())

            # Escape is a development-only way out of a fullscreen topmost window.
            # AllowClose is already true in that mode, so this cannot become an
            # exit path in a deployed package.
            if ($DevelopmentMode) {
                $window.Add_KeyDown({
                    param($eventSender, $eventArgs)
                    if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
                        $window.Close()
                    }
                }.GetNewClosure())
            }

            # Closing the window releases the job handle, and
            # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE terminates anything still
            # running as the guest.
            $window.Add_Closed({
                try { [UMD.Libraries.LibGuest.BrokerLauncher]::EndSession() } catch { }
                [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvokeShutdown(
                    [System.Windows.Threading.DispatcherPriority]::Background)
            }.GetNewClosure())

            # Show + Dispatcher.Run, NOT ShowDialog. Hiding a modal window ends
            # its ShowDialog call, so the first successful launch would unwind
            # this function, end the script, close the job handle, and kill the
            # guest's application. With an explicit dispatcher loop, Hide() just
            # hides: the loop ends only when the window actually closes.
            $window.Show()
            [System.Windows.Threading.Dispatcher]::Run()
        }
    }

    #endregion

    #region Main

    try {
        $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
        $configurationPath = Join-Path $scriptDir 'broker-settings.json'
        $xamlPath = Join-Path $scriptDir 'MainWindow.xaml'
        $nativeSourcePath = Join-Path $scriptDir 'LibGuestBrokerNative.cs'

        $settings = Get-BrokerConfiguration -Path $configurationPath
        $sessionContext = Get-SharedPcSessionContext -BrokerSessionAccountPattern $settings.BrokerSessionAccountPattern
        $guestDecision = Test-SharedPcGuestSession -SessionContext $sessionContext -Settings $settings
        $prerequisites = Test-BrokerLaunchPrerequisite

        $effectiveApplicationId = if ($PSBoundParameters.ContainsKey('ApplicationId') -and $ApplicationId) {
            $ApplicationId
        }
        else {
            $settings.DefaultApplicationId
        }

        if ($ProbeOnly) {
            $resolvedApplication = $null
            $applicationError = $null
            try {
                $resolvedApplication = Resolve-BrokerApplication -Settings $settings -ApplicationId $effectiveApplicationId
            }
            catch {
                $applicationError = $_.Exception.Message
            }

            [pscustomobject]@{
                SessionContext   = $sessionContext
                GuestDecision    = $guestDecision
                Prerequisites    = $prerequisites
                Application      = $resolvedApplication
                ApplicationError = $applicationError
            } | ConvertTo-Json -Depth 6
            return
        }

        $developmentOverride = $ForceGuestUi -and $settings.AllowDevelopmentOverrides
        if ($ForceGuestUi -and -not $settings.AllowDevelopmentOverrides) {
            # A shipped package must not be able to present a credential prompt
            # outside the gate; that would be a ready-made phishing surface on a
            # machine-wide auto-start entry.
            Write-BrokerLog -Level 'WARN' -Message '-ForceGuestUi ignored: AllowDevelopmentOverrides is false in broker-settings.json.'
            Write-Verbose '-ForceGuestUi ignored because AllowDevelopmentOverrides is false.'
        }

        if (-not $developmentOverride -and -not $guestDecision.IsGuestSession) {
            Write-Verbose "Broker UI suppressed. Failed requirements: $($guestDecision.FailedRequirements -join ', ')"
            return
        }

        if (-not $prerequisites.SecondaryLogonUsable) {
            throw "The Secondary Logon service is $($prerequisites.SecondaryLogonStartType). CreateProcessWithLogonW cannot run without it."
        }
        if ($prerequisites.IsSystemAccount) {
            throw 'CreateProcessWithLogonW cannot be called from a LocalSystem process. Run the broker as the interactive broker account.'
        }

        $application = Resolve-BrokerApplication -Settings $settings -ApplicationId $effectiveApplicationId
        Initialize-BrokerNativeLauncher -SourcePath $nativeSourcePath

        Write-BrokerLog -Level 'INFO' -Message (
            'Broker UI starting. Application={0} Mode={1} Path={2} DevelopmentOverride={3}' -f
            $application.Id, $application.Mode, $application.Path, $developmentOverride
        )

        Show-LibGuestBrokerWindow `
            -XamlPath $xamlPath `
            -Settings $settings `
            -Application $application `
            -DevelopmentMode:$developmentOverride
    }
    catch {
        $failureMessage = "LibGuest session-broker failed: $($_.Exception.Message)"
        Write-BrokerLog -Level 'ERROR' -Message $failureMessage

        try { [UMD.Libraries.LibGuest.BrokerLauncher]::EndSession() } catch { }

        # Not Write-Error: $ErrorActionPreference is 'Stop', so it would raise a
        # terminating error here and the exit code below would never run.
        [Console]::Error.WriteLine($failureMessage)
        exit 1
    }

    #endregion
}
