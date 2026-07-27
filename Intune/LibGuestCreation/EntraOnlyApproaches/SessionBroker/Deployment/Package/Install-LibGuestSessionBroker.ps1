<#
.SYNOPSIS
    Installs the LibGuest session broker as an Intune Win32 app.

.DESCRIPTION
    Runs non-interactively as SYSTEM. Performs the complete device configuration:

      1. Stages the broker files to C:\ProgramData\LibGuestSessionBroker\Prototype
      2. Locks down the install root so guest accounts cannot modify the broker
         or its configuration, while leaving broker.log writable
      3. Applies guest session policy to the Default user hive
      4. Applies machine-wide Microsoft Edge policy
      5. Registers the broker for auto-start via the All Users Startup folder
      6. Writes the registry sentinel that detection keys on

    Written to work both ways without edits:
      A. powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-LibGuestSessionBroker.ps1
      B. pasted into the Intune Win32 "PowerShell script installer" box

    Method A is preferred. It keeps the script versioned inside the package, and
    it is the only form that can relaunch itself in 64-bit PowerShell (see below).

.PARAMETER InstallRoot
    Where the broker is staged.

.PARAMETER SkipEdgePolicy
    Leaves Microsoft Edge policy untouched. Use when Edge configuration is managed
    by a separate Settings Catalog profile.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-LibGuestSessionBroker.ps1

.NOTES
    Author:  Oji / UMD Libraries
    Date:    2026-07-27
    Version: 0.3.0

    Exit codes: 0 success, 1 failure. No reboot is required, so 3010 is never
    returned.

    BITNESS: the Intune Management Extension may invoke this in 32-bit
    PowerShell. Registry writes would then land in WOW6432Node and detection would
    never match. The script relaunches itself through SysNative when it detects
    that case, which requires $PSCommandPath — one more reason Method A is the
    default.

    IDEMPOTENT: safe to re-run. Intune upgrades run install over the top.
#>

[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\ProgramData\LibGuestSessionBroker',

    [switch]$SkipEdgePolicy
)

begin {
    $ErrorActionPreference = 'Stop'
    $productVersion = '0.3.2'
    $sentinelSubKey = 'SOFTWARE\UMDLibraries\LibGuestSessionBroker'
}

end {
    $logPath = Join-Path $InstallRoot 'install.log'

    function Set-SentinelValues {
        <#
        .SYNOPSIS
            Writes the detection sentinel into the 64-bit registry view.
        .DESCRIPTION
            Explicitly 64-bit rather than relying on the host process bitness.
            The Intune Management Extension may run this in 32-bit PowerShell, and
            HKLM\SOFTWARE is redirected: the sentinel would land in WOW6432Node
            where the detection script never looks, so every device would report as
            not installed and reinstall on every check-in.

            An explicit view is used instead of relaunching through SysNative
            because a relaunch needs $PSCommandPath, which is empty when this
            script is pasted into Intune's PowerShell installer box.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-27
            Version: 0.3.0
        #>
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)][string]$SubKeyPath,
            [Parameter(Mandatory)][hashtable]$Values
        )
        process {
            if (-not $PSCmdlet.ShouldProcess("HKLM64:\$SubKeyPath", 'Write sentinel')) { return }

            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine,
                [Microsoft.Win32.RegistryView]::Registry64)
            try {
                $subKey = $baseKey.CreateSubKey($SubKeyPath)
                try {
                    foreach ($name in $Values.Keys) {
                        $subKey.SetValue($name, $Values[$name], [Microsoft.Win32.RegistryValueKind]::String)
                    }
                }
                finally { $subKey.Dispose() }
            }
            finally { $baseKey.Dispose() }
        }
    }

    function Write-InstallLog {
        <#
        .SYNOPSIS
            Appends a line to the install log and echoes it for the Intune log.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-27
            Version: 0.3.0
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
                if (-not (Test-Path -LiteralPath $InstallRoot)) {
                    New-Item -Path $InstallRoot -ItemType Directory -Force | Out-Null
                }
                Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
            }
            catch {
                # Logging must never fail the install.
            }
        }
    }

    function Invoke-PackagedScript {
        <#
        .SYNOPSIS
            Runs a bundled configuration script as a child process and checks its exit code.
        .DESCRIPTION
            A child powershell.exe rather than dot-sourcing or '&': the bundled
            scripts call exit on failure, and a separate process makes that exit
            code unambiguous instead of depending on how the caller invoked them.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-27
            Version: 0.3.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Path,
            [string[]]$ScriptArguments = @()
        )
        process {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                throw "Bundled script missing from package: $Path"
            }

            $powerShellExe = Join-Path $PSHOME 'powershell.exe'
            $arguments = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', $Path) + $ScriptArguments

            & $powerShellExe @arguments | ForEach-Object { Write-InstallLog -Level 'INFO' -Message "    $_" }

            if ($LASTEXITCODE -ne 0) {
                throw "$(Split-Path $Path -Leaf) failed with exit code $LASTEXITCODE."
            }
        }
    }

    function Set-InstallRootAcl {
        <#
        .SYNOPSIS
            Restricts the install root so guest accounts cannot alter the broker.
        .DESCRIPTION
            The broker's behavior is entirely driven by broker-settings.json. A
            guest account with write access there could widen
            AllowedApplicationRoots or point Applications at an arbitrary binary,
            which would then run against a live SIMS credential.

            broker.log is granted Modify separately so the broker can still log
            while running as an unprivileged guest account.

            Well-known SIDs rather than account names, so this works on a
            non-English Windows install.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-27
            Version: 0.3.0
        #>
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)][string]$Path
        )
        process {
            if (-not $PSCmdlet.ShouldProcess($Path, 'Apply restrictive ACL')) { return }

            $administrators = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
            $localSystem = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
            $users = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')

            $acl = Get-Acl -LiteralPath $Path
            $acl.SetAccessRuleProtection($true, $false)
            foreach ($rule in @($acl.Access)) {
                $null = $acl.RemoveAccessRule($rule)
            }

            foreach ($identity in @($administrators, $localSystem)) {
                $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
            }
            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                $users, 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))

            Set-Acl -LiteralPath $Path -AclObject $acl

            # Logging is best-effort in the broker, but losing it on a fleet device
            # means losing the only record of why a guest session failed.
            $brokerLog = Join-Path $Path 'broker.log'
            if (-not (Test-Path -LiteralPath $brokerLog)) {
                New-Item -Path $brokerLog -ItemType File -Force | Out-Null
            }
            $logAcl = Get-Acl -LiteralPath $brokerLog
            $logAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                $users, 'Modify', 'None', 'None', 'Allow')))
            Set-Acl -LiteralPath $brokerLog -AclObject $logAcl

            # Session accountability CSV: guests may APPEND rows (the broker and
            # its watcher run as the guest, so they must be able to write) but get
            # no WriteData or Delete, so history cannot be rewritten or erased
            # from a guest session. Administrators retain full control.
            $auditCsv = Join-Path $Path 'sessions.csv'
            if (-not (Test-Path -LiteralPath $auditCsv)) {
                Set-Content -LiteralPath $auditCsv `
                    -Value 'Timestamp,ComputerName,Event,GuestAccount,Application,SessionId,DurationMinutes,Detail' `
                    -Encoding UTF8
            }
            $csvAcl = Get-Acl -LiteralPath $auditCsv
            $csvAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                $users, 'AppendData', 'None', 'None', 'Allow')))
            Set-Acl -LiteralPath $auditCsv -AclObject $csvAcl

            # Session heartbeat state. Users get Modify because the watcher
            # overwrites it every heartbeat, unlike the append-only audit CSV.
            # Pre-created here and never deleted at runtime: a file recreated by a
            # guest would inherit the folder ACL, which is read-only for Users, and
            # the next guest could not write it.
            $sessionState = Join-Path $Path 'session-state.json'
            if (-not (Test-Path -LiteralPath $sessionState)) {
                Set-Content -LiteralPath $sessionState -Value '' -Encoding UTF8
            }
            $stateAcl = Get-Acl -LiteralPath $sessionState
            $stateAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                $users, 'Modify', 'None', 'None', 'Allow')))
            Set-Acl -LiteralPath $sessionState -AclObject $stateAcl
        }
    }

    try {
        # $PSScriptRoot is empty when this script is pasted into Intune rather than
        # run with -File. The working directory is the unpacked package either way.
        $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

        Write-InstallLog -Level 'INFO' -Message "=== Installing LibGuest session broker $productVersion ==="
        Write-InstallLog -Level 'INFO' -Message "Package source: $scriptDir"
        Write-InstallLog -Level 'INFO' -Message "64-bit process: $([Environment]::Is64BitProcess)"

        $sourcePrototype = Join-Path $scriptDir 'Prototype'
        $sourceContainment = Join-Path $scriptDir 'Containment'
        $targetPrototype = Join-Path $InstallRoot 'Prototype'

        if (-not (Test-Path -LiteralPath $sourcePrototype -PathType Container)) {
            throw "Package is missing its Prototype folder: $sourcePrototype"
        }

        # Fail before changing anything rather than leaving a half-configured device.
        foreach ($required in @('Start-LibGuestSessionBroker.ps1', 'LibGuestBrokerNative.cs', 'MainWindow.xaml', 'broker-settings.json', 'Watch-GuestSession.ps1')) {
            $requiredPath = Join-Path $sourcePrototype $required
            if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
                throw "Package is missing a required broker file: $required"
            }
        }

        # Configuration sanity, checked on the device rather than at build time so
        # a hand-assembled package cannot bypass it.
        $packagedSettings = Get-Content -LiteralPath (Join-Path $sourcePrototype 'broker-settings.json') -Raw | ConvertFrom-Json

        if ($packagedSettings.AllowDevelopmentOverrides) {
            # -ForceGuestUi would render a UMD-branded credential prompt outside the
            # session gate, on a machine-wide auto-start entry. That is a
            # ready-made phishing surface and must never reach a fleet device.
            throw 'broker-settings.json has AllowDevelopmentOverrides set to true. Refusing to install a package that can show a credential prompt outside the session gate.'
        }

        $defaultApplication = @($packagedSettings.Applications | Where-Object { $_.Id -eq $packagedSettings.DefaultApplicationId })[0]
        Write-InstallLog -Level 'INFO' -Message "Broker default application: $($packagedSettings.DefaultApplicationId) (Mode $($defaultApplication.Mode))"
        if ($defaultApplication.Mode -eq 'IdentityTest') {
            Write-InstallLog -Level 'WARN' -Message 'Default application is in IdentityTest mode: patrons will authenticate and receive no application.'
        }

        Write-InstallLog -Level 'INFO' -Message "Staging broker files to $targetPrototype"
        if (-not (Test-Path -LiteralPath $targetPrototype)) {
            New-Item -Path $targetPrototype -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path (Join-Path $sourcePrototype '*') -Destination $targetPrototype -Recurse -Force
        Get-ChildItem -LiteralPath $targetPrototype -Recurse -File | Unblock-File

        Write-InstallLog -Level 'INFO' -Message "Applying install root ACL"
        Set-InstallRootAcl -Path $InstallRoot

        Write-InstallLog -Level 'INFO' -Message 'Applying guest session policy to the Default user hive'
        Invoke-PackagedScript -Path (Join-Path $sourceContainment 'Set-GuestSessionLockdown.ps1')

        if ($SkipEdgePolicy) {
            Write-InstallLog -Level 'WARN' -Message 'Skipping Edge policy at caller request.'
        }
        else {
            Write-InstallLog -Level 'INFO' -Message 'Applying machine-wide Microsoft Edge policy'
            Invoke-PackagedScript -Path (Join-Path $sourceContainment 'Set-EdgeContainmentPolicy.ps1')
        }

        Write-InstallLog -Level 'INFO' -Message 'Registering broker auto-start'
        Invoke-PackagedScript `
            -Path (Join-Path $sourceContainment 'Install-BrokerAutoStart.ps1') `
            -ScriptArguments @('-BrokerPath', (Join-Path $targetPrototype 'Start-LibGuestSessionBroker.ps1'))

        # Written last, on purpose. Detection keys on this value, so it must only
        # exist when every step above has succeeded.
        Write-InstallLog -Level 'INFO' -Message "Writing detection sentinel HKLM:\$sentinelSubKey (64-bit view)"
        Set-SentinelValues -SubKeyPath $sentinelSubKey -Values @{
            Version     = $productVersion
            InstalledOn = (Get-Date).ToString('o')
            InstallPath = $InstallRoot
        }

        Write-InstallLog -Level 'INFO' -Message '=== Install complete ==='
        Write-InstallLog -Level 'WARN' -Message 'Guest profiles created before this install keep the old policy. Sign out and back in to pick it up.'
        exit 0
    }
    catch {
        Write-InstallLog -Level 'ERROR' -Message "Install failed: $($_.Exception.Message)"
        Write-InstallLog -Level 'ERROR' -Message $_.ScriptStackTrace
        [Console]::Error.WriteLine("Install failed: $($_.Exception.Message)")
        exit 1
    }
}
