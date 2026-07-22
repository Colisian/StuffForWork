<#
.SYNOPSIS
    Starts the LibGuest session-broker prototype only in a Shared PC guest session.

.DESCRIPTION
    Evaluates the current interactive identity before loading any UI. The broker
    window opens only when the current account is local, Shared PC configuration is
    present, and the current username matches the configured disposable-account
    pattern. All other sessions exit without displaying a window.

    Use -ProbeOnly inside a Shared PC Guest session to collect the sanitized session
    markers needed to validate the launch gate before deployment.

.PARAMETER ProbeOnly
    Writes the sanitized session-context result as JSON and does not display the UI.

.PARAMETER ForceGuestUi
    Displays the prototype UI without passing the guest-session gate. Intended only
    for UI development on a test workstation.

.NOTES
    Author:  Oji / UMD Libraries
    Date:    2026-07-22
    Version: 0.1.0

    This prototype does not authenticate credentials or launch an application.
#>

[CmdletBinding()]
param(
    [switch]$ProbeOnly,
    [switch]$ForceGuestUi
)

begin {
    $ErrorActionPreference = 'Stop'
}

end {
    function Get-BrokerConfiguration {
        <#
        .SYNOPSIS
            Loads and validates the session-broker configuration.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-22
            Version: 0.1.0
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

            $configuration = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 |
                ConvertFrom-Json

            if ([string]::IsNullOrWhiteSpace($configuration.GuestAccountPattern)) {
                throw 'GuestAccountPattern is required in broker-settings.json.'
            }

            if ($configuration.MinimumGuestNumber -lt 1 -or
                $configuration.MaximumGuestNumber -lt $configuration.MinimumGuestNumber) {
                throw 'The configured guest-number range is invalid.'
            }

            return $configuration
        }
    }

    function Get-SharedPcSessionContext {
        <#
        .SYNOPSIS
            Returns sanitized identity and Shared PC markers for the current session.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-22
            Version: 0.1.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$GuestAccountPattern
        )

        begin {
            $ErrorActionPreference = 'Stop'
        }

        process {
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $identityName = $identity.Name
            $currentSid = $identity.User.Value
            $userName = $env:USERNAME
            $userDomain = $env:USERDOMAIN
            $computerName = $env:COMPUTERNAME
            $groupSids = @($identity.Groups | ForEach-Object { $_.Value })

            $sharedPcPaths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedPC',
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedPC\NodeValues',
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedPC\AccountManagement'
            )
            $sharedPcPathsFound = @(
                $sharedPcPaths | Where-Object { Test-Path -LiteralPath $_ }
            )

            $isLocalAccount = $userDomain -ieq $computerName
            $matchesGuestPattern = $userName -match $GuestAccountPattern
            $isGuestsGroupMember = $groupSids -contains 'S-1-5-32-546'
            $isUsersGroupMember = $groupSids -contains 'S-1-5-32-545'
            $isSharedPcConfigured = $sharedPcPathsFound.Count -gt 0

            [pscustomobject]@{
                SchemaVersion             = 1
                CollectedAt               = (Get-Date).ToString('o')
                ComputerName              = $computerName
                IdentityName              = $identityName
                UserName                  = $userName
                UserDomain                = $userDomain
                UserSid                   = $currentSid
                IsLocalAccount            = $isLocalAccount
                MatchesGuestPattern       = $matchesGuestPattern
                IsGuestsGroupMember       = $isGuestsGroupMember
                IsUsersGroupMember        = $isUsersGroupMember
                IsSharedPcConfigured      = $isSharedPcConfigured
                SharedPcRegistryPathsFound = $sharedPcPathsFound
            }
        }
    }

    function Test-SharedPcGuestSession {
        <#
        .SYNOPSIS
            Determines whether the current session should display the broker UI.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-22
            Version: 0.1.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [psobject]$SessionContext,

            [Parameter(Mandatory)]
            [psobject]$Configuration
        )

        begin {
            $ErrorActionPreference = 'Stop'
        }

        process {
            $requirements = [ordered]@{
                GuestAccountPattern = [bool]$SessionContext.MatchesGuestPattern
            }

            if ($Configuration.RequireLocalAccount) {
                $requirements.LocalAccount = [bool]$SessionContext.IsLocalAccount
            }

            if ($Configuration.RequireSharedPcRegistry) {
                $requirements.SharedPcConfigured = [bool]$SessionContext.IsSharedPcConfigured
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

    function Show-LibGuestBrokerWindow {
        <#
        .SYNOPSIS
            Displays the nonfunctional WPF shell for the broker prototype.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-22
            Version: 0.1.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$XamlPath,

            [Parameter(Mandatory)]
            [int]$MinimumGuestNumber,

            [Parameter(Mandatory)]
            [int]$MaximumGuestNumber,

            [Parameter(Mandatory)]
            [string]$Realm
        )

        begin {
            $ErrorActionPreference = 'Stop'
        }

        process {
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

            $signInButton.Add_Click({
                $statusTextBlock.Text = ''
                $rawGuestNumber = $guestNumberTextBox.Text.Trim()
                $numberText = $rawGuestNumber -replace '^(?i:libguest)', ''
                $guestNumber = 0

                if (-not [int]::TryParse($numberText, [ref]$guestNumber) -or
                    $guestNumber -lt $MinimumGuestNumber -or
                    $guestNumber -gt $MaximumGuestNumber) {
                    $statusTextBlock.Text = "Enter a guest number from $MinimumGuestNumber through $MaximumGuestNumber."
                    $guestNumberTextBox.Focus() | Out-Null
                    return
                }

                if ($guestPasswordBox.SecurePassword.Length -eq 0) {
                    $statusTextBlock.Text = 'Enter the password issued by library staff.'
                    $guestPasswordBox.Focus() | Out-Null
                    return
                }

                $principal = "libguest$guestNumber@$Realm"
                $guestPasswordBox.Clear()
                $statusTextBlock.Foreground = '#555555'
                $statusTextBlock.Text = "Validated $principal. Authentication and application launch will be added in the next milestone."
            })

            $guestNumberTextBox.Focus() | Out-Null
            $window.ShowDialog() | Out-Null
        }
    }

    try {
        $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
        $configurationPath = Join-Path $scriptDir 'broker-settings.json'
        $xamlPath = Join-Path $scriptDir 'MainWindow.xaml'
        $configuration = Get-BrokerConfiguration -Path $configurationPath
        $sessionContext = Get-SharedPcSessionContext `
            -GuestAccountPattern $configuration.GuestAccountPattern
        $guestDecision = Test-SharedPcGuestSession `
            -SessionContext $sessionContext `
            -Configuration $configuration

        if ($ProbeOnly) {
            [pscustomobject]@{
                SessionContext = $sessionContext
                GuestDecision  = $guestDecision
            } | ConvertTo-Json -Depth 6
            return
        }

        if (-not $ForceGuestUi -and -not $guestDecision.IsGuestSession) {
            Write-Verbose "Broker UI suppressed. Failed requirements: $($guestDecision.FailedRequirements -join ', ')"
            return
        }

        Show-LibGuestBrokerWindow `
            -XamlPath $xamlPath `
            -MinimumGuestNumber $configuration.MinimumGuestNumber `
            -MaximumGuestNumber $configuration.MaximumGuestNumber `
            -Realm $configuration.Realm
    }
    catch {
        Write-Error "LibGuest session-broker prototype failed: $($_.Exception.Message)"
        exit 1
    }
}
