<#
.SYNOPSIS
    Validates broker-settings.json handling and gate logic without touching Windows.

.DESCRIPTION
    Extracts the pure-logic functions from Start-LibGuestSessionBroker.ps1 and
    exercises them against the shipping configuration plus a set of deliberately
    broken ones. Every malformed configuration must be REJECTED: the gate is a
    security control, so a missing or mistyped setting has to fail the load rather
    than silently drop the requirement it controls.

    Cross-platform. Runs under pwsh on macOS or Linux, so it can gate a commit
    before any Windows device is involved.

.EXAMPLE
    pwsh -NoProfile -File ./Test-BrokerConfiguration.ps1

.NOTES
    Author:  Oji / UMD Libraries
    Date:    2026-07-26
    Version: 0.2.0

    Exit codes: 0 all checks passed, 1 one or more failed.
#>

[CmdletBinding()]
param()

begin {
    $ErrorActionPreference = 'Stop'
}

end {
    $script:failureCount = 0

    function Write-Result {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][bool]$Passed,
            [Parameter(Mandatory)][string]$Label,
            [string]$Detail
        )
        process {
            if (-not $Passed) { $script:failureCount++ }
            $tag = if ($Passed) { 'PASS' } else { 'FAIL' }
            Write-Host ('  [{0}] {1,-36} {2}' -f $tag, $Label, $Detail)
        }
    }

    $prototypePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Deployment/Package/Prototype'
    $brokerScript = Join-Path $prototypePath 'Start-LibGuestSessionBroker.ps1'
    $settingsPath = Join-Path $prototypePath 'broker-settings.json'

    foreach ($required in @($brokerScript, $settingsPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required file not found: $required"
        }
    }

    Write-Host "`nParsing Start-LibGuestSessionBroker.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($brokerScript, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) {
        $parseErrors | ForEach-Object {
            Write-Result -Passed $false -Label 'parse' -Detail "line $($_.Extent.StartLineNumber): $($_.Message)"
        }
        exit 1
    }
    Write-Result -Passed $true -Label 'script parses' -Detail ''

    # Pull only the platform-independent functions into this session.
    $wanted = 'Get-BrokerSettingValue', 'Get-BrokerConfiguration', 'Test-SharedPcGuestSession', 'Get-BrokerLogonFailureCategory'
    $source = ($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $wanted
    }, $true) | ForEach-Object { $_.Extent.Text }) -join "`n"
    . ([scriptblock]::Create($source))

    function Test-ConfigurationLoad {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Json,
            [Parameter(Mandatory)][string]$Label,
            [switch]$ExpectReject
        )
        process {
            $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ('broker-cfg-{0}.json' -f [guid]::NewGuid())
            Set-Content -LiteralPath $tempPath -Value $Json -Encoding utf8
            try {
                $null = Get-BrokerConfiguration -Path $tempPath
                $rejected = $false
                $detail = 'LOADED'
            }
            catch {
                $rejected = $true
                $detail = 'REJECTED: ' + $_.Exception.Message
            }
            finally {
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            }
            Write-Result -Passed ($rejected -eq [bool]$ExpectReject) -Label $Label -Detail $detail
        }
    }

    $good = Get-Content -LiteralPath $settingsPath -Raw
    $quote = [char]34

    function Set-JsonValue {
        param([string]$Json, [string]$Key, [string]$OldValue, [string]$NewValue)
        $old = '{0}{1}{0}: {2}' -f $quote, $Key, $OldValue
        $new = '{0}{1}{0}: {2}' -f $quote, $Key, $NewValue
        return $Json.Replace($old, $new)
    }

    Write-Host "`nShipping configuration"
    Test-ConfigurationLoad -Json $good -Label 'loads as shipped'

    Write-Host "`nFail-closed checks (each must be REJECTED)"
    Test-ConfigurationLoad -ExpectReject -Label 'RequireLocalAccount key typo' `
        -Json $good.Replace($quote + 'RequireLocalAccount' + $quote, $quote + 'RequireLocalAcount' + $quote)
    Test-ConfigurationLoad -ExpectReject -Label 'boolean supplied as JSON string' `
        -Json (Set-JsonValue $good 'RequireSharedPcRegistry' 'true' ($quote + 'true' + $quote))
    Test-ConfigurationLoad -ExpectReject -Label 'unanchored account pattern' `
        -Json $good.Replace('^shpc[a-z0-9]+$', 'shpc')
    Test-ConfigurationLoad -ExpectReject -Label 'invalid regex in account pattern' `
        -Json $good.Replace('^shpc[a-z0-9]+$', '^shpc[a-z0-9+$')
    # Matched by key, not by current value: these must keep working when the
    # shipping configuration changes which application is the default.
    Test-ConfigurationLoad -ExpectReject -Label 'unknown application Mode' `
        -Json ([regex]::Replace($good, '"Mode":\s*"[^"]*"', '"Mode": "Whatever"'))
    Test-ConfigurationLoad -ExpectReject -Label 'DefaultApplicationId not in allowlist' `
        -Json ([regex]::Replace($good, '"DefaultApplicationId":\s*"[^"]*"', '"DefaultApplicationId": "Nope"'))
    Test-ConfigurationLoad -ExpectReject -Label 'MinimumGuestNumber below 1' `
        -Json (Set-JsonValue $good 'MinimumGuestNumber' '1' '0')
    Test-ConfigurationLoad -ExpectReject -Label 'MaximumGuestNumber below minimum' `
        -Json (Set-JsonValue $good 'MaximumGuestNumber' '500' '0')
    Test-ConfigurationLoad -ExpectReject -Label 'SessionTimeoutMinutes zero' `
        -Json (Set-JsonValue $good 'SessionTimeoutMinutes' '60' '0')
    Test-ConfigurationLoad -ExpectReject -Label 'empty Applications array' `
        -Json ([regex]::Replace($good, '(?s)"Applications":\s*\[.*?\n  \]', '"Applications": []'))

    Write-Host "`nGate evaluation (RequireGuestsGroup off, as shipped)"
    $settings = [pscustomobject]@{
        RequireLocalAccount     = $true
        RequireSharedPcRegistry = $true
        RequireGuestsGroup      = $false
    }
    $scenarios = @(
        @{
            Label   = 'Shared PC guest session'
            Expect  = $true
            Context = [pscustomobject]@{
                MatchesBrokerAccountPattern = $true; IsLocalAccount = $true
                IsSharedPcConfigured = $true; IsGuestsGroupMember = $false
            }
        },
        @{
            Label   = 'Entra / domain session'
            Expect  = $false
            Context = [pscustomobject]@{
                MatchesBrokerAccountPattern = $false; IsLocalAccount = $false
                IsSharedPcConfigured = $true; IsGuestsGroupMember = $false
            }
        },
        @{
            Label   = 'local account, wrong name shape'
            Expect  = $false
            Context = [pscustomobject]@{
                MatchesBrokerAccountPattern = $false; IsLocalAccount = $true
                IsSharedPcConfigured = $true; IsGuestsGroupMember = $false
            }
        },
        @{
            Label   = 'right name, Shared PC not configured'
            Expect  = $false
            Context = [pscustomobject]@{
                MatchesBrokerAccountPattern = $true; IsLocalAccount = $true
                IsSharedPcConfigured = $false; IsGuestsGroupMember = $false
            }
        }
    )
    foreach ($scenario in $scenarios) {
        $decision = Test-SharedPcGuestSession -SessionContext $scenario.Context -Settings $settings
        Write-Result -Passed ($decision.IsGuestSession -eq $scenario.Expect) -Label $scenario.Label `
            -Detail ('IsGuestSession={0} Failed=[{1}]' -f $decision.IsGuestSession, ($decision.FailedRequirements -join ','))
    }

    Write-Host "`nWin32 error classification"
    $errorCases = @(
        @{ Code = 1326; Expect = 'Credential' }      # ERROR_LOGON_FAILURE
        @{ Code = 1331; Expect = 'Credential' }      # ERROR_ACCOUNT_DISABLED
        @{ Code = 1909; Expect = 'Credential' }      # ERROR_ACCOUNT_LOCKED_OUT
        @{ Code = 1907; Expect = 'Credential' }      # ERROR_PASSWORD_MUST_CHANGE
        @{ Code = 1311; Expect = 'Infrastructure' }  # ERROR_NO_LOGON_SERVERS
        @{ Code = 1058; Expect = 'Infrastructure' }  # ERROR_SERVICE_DISABLED
        @{ Code = 2;    Expect = 'Infrastructure' }  # ERROR_FILE_NOT_FOUND
    )
    foreach ($case in $errorCases) {
        $actual = Get-BrokerLogonFailureCategory -Win32Error $case.Code
        Write-Result -Passed ($actual -eq $case.Expect) -Label ('error {0}' -f $case.Code) -Detail $actual
    }

    Write-Host ''
    if ($script:failureCount -gt 0) {
        Write-Host ('{0} check(s) FAILED' -f $script:failureCount) -ForegroundColor Red
        exit 1
    }
    Write-Host 'All checks passed.' -ForegroundColor Green
    exit 0
}
