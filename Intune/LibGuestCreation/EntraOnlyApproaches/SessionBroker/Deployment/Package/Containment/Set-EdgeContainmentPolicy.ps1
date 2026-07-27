<#
.SYNOPSIS
    Applies machine-wide Microsoft Edge policy for the LibGuest public browsing session.

.DESCRIPTION
    Writes Edge policy under HKLM so it reaches every account on the device,
    including the local libguestN accounts.

    This scoping is not a style choice. The libguestN accounts are local SAM
    accounts with no Entra identity, so a user-targeted Intune configuration
    profile will never apply to them. Only device-scoped (HKLM) policy reaches the
    security context the patron's browser actually runs in.

    Two policy groups are applied:

      Containment  - reduces the ways a patron can escape the browser into the
                     filesystem or another application.
      Privacy      - reduces what one patron leaves behind for the next.

    This script exists so containment can be tested immediately, without waiting
    on an Intune sync. The production path is the Intune Settings Catalog
    (Microsoft Edge). Keep the two in agreement.

.PARAMETER Remove
    Removes the policy keys this script manages and restores default Edge behavior.

.PARAMETER LogPath
    Override the default log location.

.EXAMPLE
    .\Set-EdgeContainmentPolicy.ps1

.EXAMPLE
    .\Set-EdgeContainmentPolicy.ps1 -Remove

.NOTES
    Author:  Oji / UMD Libraries
    Date:    2026-07-27
    Version: 0.1.0

    Requires administrative rights. Edge must be fully restarted to pick up
    changes; a running instance keeps the old policy.

    VERIFY, DO NOT ASSUME. After running this, open edge://policy in the target
    session and confirm every value below appears with status "OK". A policy name
    that Edge does not recognise is silently ignored, which fails open. edge://policy
    is the only reliable confirmation that a control is actually in force.

    Machine-wide policy applies to administrators using Edge on this device too.
    That is an accepted trade on a dedicated public workstation.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Remove,

    [string]$LogPath = 'C:\ProgramData\LibGuestSessionBroker\edge-containment.log'
)

begin {
    $ErrorActionPreference = 'Stop'
    $edgePolicyRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
}

end {
    function Write-ContainmentLog {
        <#
        .SYNOPSIS
            Appends a line to the containment log and echoes it to the console.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-27
            Version: 0.1.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level,
            [Parameter(Mandatory)][string]$Message
        )
        process {
            $line = '{0} {1} {2}' -f (Get-Date).ToString('o'), $Level, $Message
            Write-Host $line
            try {
                $directory = Split-Path -Path $LogPath -Parent
                if (-not (Test-Path -LiteralPath $directory)) {
                    New-Item -Path $directory -ItemType Directory -Force | Out-Null
                }
                Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
            }
            catch {
                # Logging must never take the policy application down.
            }
        }
    }

    function Set-PolicyValue {
        <#
        .SYNOPSIS
            Writes a single Edge policy value.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-27
            Version: 0.1.0
        #>
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)]$Value,
            [Parameter(Mandatory)][ValidateSet('DWord', 'String')][string]$Type,
            [Parameter(Mandatory)][string]$Rationale
        )
        process {
            if (-not $PSCmdlet.ShouldProcess("$Path\$Name", "Set to $Value")) { return }
            if (-not (Test-Path -LiteralPath $Path)) {
                New-Item -Path $Path -Force | Out-Null
            }
            Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type $Type -Force
            Write-ContainmentLog -Level 'INFO' -Message ('  {0} = {1}  ({2})' -f $Name, $Value, $Rationale)
        }
    }

    function Set-PolicyList {
        <#
        .SYNOPSIS
            Writes a numbered-value Edge policy list, replacing any existing entries.
        .DESCRIPTION
            List policies such as URLBlocklist are stored as a subkey containing
            string values named "1", "2", ... The key is recreated so a shortened
            list never leaves stale entries behind.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-27
            Version: 0.1.0
        #>
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string[]]$Values,
            [Parameter(Mandatory)][string]$Rationale
        )
        process {
            if (-not $PSCmdlet.ShouldProcess($Path, 'Replace policy list')) { return }
            if (Test-Path -LiteralPath $Path) {
                Remove-Item -LiteralPath $Path -Recurse -Force
            }
            New-Item -Path $Path -Force | Out-Null
            for ($index = 0; $index -lt $Values.Count; $index++) {
                Set-ItemProperty -LiteralPath $Path -Name ([string]($index + 1)) -Value $Values[$index] -Type String -Force
            }
            Write-ContainmentLog -Level 'INFO' -Message ('  {0} = [{1}]  ({2})' -f (Split-Path $Path -Leaf), ($Values -join ', '), $Rationale)
        }
    }

    try {
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
        if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'This script must run elevated: it writes to HKLM.'
        }

        if ($Remove) {
            Write-ContainmentLog -Level 'INFO' -Message '=== Removing Edge containment policy ==='
            if (Test-Path -LiteralPath $edgePolicyRoot) {
                if ($PSCmdlet.ShouldProcess($edgePolicyRoot, 'Remove policy key')) {
                    Remove-Item -LiteralPath $edgePolicyRoot -Recurse -Force
                    Write-ContainmentLog -Level 'INFO' -Message 'Removed.'
                }
            }
            else {
                Write-ContainmentLog -Level 'INFO' -Message 'Nothing to remove.'
            }
            Write-ContainmentLog -Level 'WARN' -Message 'Restart Edge completely for this to take effect.'
            return
        }

        Write-ContainmentLog -Level 'INFO' -Message '=== Applying Edge containment policy ==='

        Write-ContainmentLog -Level 'INFO' -Message 'Containment:'

        # The single most important control here. Without file dialogs there is no
        # Ctrl+O, no Save As, and no upload browser, which removes the Windows
        # common file dialog entirely. That dialog is a classic escape: it browses
        # the filesystem and can launch executables from its context menu.
        Set-PolicyValue -Path $edgePolicyRoot -Name 'AllowFileSelectionDialogs' -Value 0 -Type 'DWord' `
            -Rationale 'removes the common file dialog escape'

        # 3 = block all downloads. Also removes the downloads bar, and with it the
        # "Open" and "Show in folder" actions that launch other programs.
        Set-PolicyValue -Path $edgePolicyRoot -Name 'DownloadRestrictions' -Value 3 -Type 'DWord' `
            -Rationale 'no downloaded executables, no Show in folder'

        # 2 = disallow developer tools on all sites.
        Set-PolicyValue -Path $edgePolicyRoot -Name 'DeveloperToolsAvailability' -Value 2 -Type 'DWord' `
            -Rationale 'removes devtools'

        Set-PolicyValue -Path $edgePolicyRoot -Name 'BrowserSignin' -Value 0 -Type 'DWord' `
            -Rationale 'no signing a personal account into the browser'

        Set-PolicyValue -Path $edgePolicyRoot -Name 'SyncDisabled' -Value 1 -Type 'DWord' `
            -Rationale 'no profile sync off the device'

        # Blocks navigation to local files, the settings surface, and protocol
        # handlers that hand control to other applications.
        Set-PolicyList -Path (Join-Path $edgePolicyRoot 'URLBlocklist') -Rationale 'blocks local and OS navigation' -Values @(
            'file://*'
            'ftp://*'
            'ms-settings:*'
            'ms-cxh:*'
            'search-ms:*'
            'shell:*'
            'view-source:*'
            'edge://settings*'
            'edge://extensions*'
            'edge://flags*'
            'edge://system*'
            'edge://net-export*'
        )

        Set-PolicyList -Path (Join-Path $edgePolicyRoot 'ExtensionInstallBlocklist') -Rationale 'no extensions' -Values @('*')

        # Local printers stay: Pharos release printing is a required service.
        # The PDF destination goes, because "Save as PDF" opens a save dialog.
        Set-PolicyList -Path (Join-Path $edgePolicyRoot 'PrinterTypeDenyList') -Rationale 'keeps local printers, drops Save as PDF' -Values @(
            'pdf'
            'cloud'
            'privet'
            'extension'
        )

        Write-ContainmentLog -Level 'INFO' -Message 'Privacy:'

        # 2 = InPrivate forced. Every patron session is private by construction, so
        # history, cookies, and cache do not survive to the next patron even if
        # broker-side cleanup fails.
        Set-PolicyValue -Path $edgePolicyRoot -Name 'InPrivateModeAvailability' -Value 2 -Type 'DWord' `
            -Rationale 'forced InPrivate; nothing persists between patrons'

        Set-PolicyValue -Path $edgePolicyRoot -Name 'PasswordManagerEnabled' -Value 0 -Type 'DWord' `
            -Rationale 'never offer to save a patron password'

        Set-PolicyValue -Path $edgePolicyRoot -Name 'AutofillAddressEnabled' -Value 0 -Type 'DWord' `
            -Rationale 'no retained personal data'

        Set-PolicyValue -Path $edgePolicyRoot -Name 'AutofillCreditCardEnabled' -Value 0 -Type 'DWord' `
            -Rationale 'no retained payment data'

        Set-PolicyValue -Path $edgePolicyRoot -Name 'UserFeedbackAllowed' -Value 0 -Type 'DWord' `
            -Rationale 'no feedback surface that can attach screenshots'

        Set-PolicyValue -Path $edgePolicyRoot -Name 'SmartScreenEnabled' -Value 1 -Type 'DWord' `
            -Rationale 'keep phishing and malware protection on'

        Write-ContainmentLog -Level 'INFO' -Message '=== Applied ==='
        Write-ContainmentLog -Level 'WARN' -Message 'Restart Edge completely, then open edge://policy and confirm every value shows status OK.'
        Write-ContainmentLog -Level 'WARN' -Message 'A policy name Edge does not recognise is ignored silently. edge://policy is the only proof.'
    }
    catch {
        $message = "Edge containment policy failed: $($_.Exception.Message)"
        Write-ContainmentLog -Level 'ERROR' -Message $message
        [Console]::Error.WriteLine($message)
        exit 1
    }
}
