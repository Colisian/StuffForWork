<#
.SYNOPSIS
    Removes the LibGuest session broker installed by the Intune Win32 app.

.DESCRIPTION
    Runs non-interactively as SYSTEM. Reverses the install in the opposite order:

      1. Removes the auto-start shortcut, so no new guest session starts the broker
      2. Removes machine-wide Microsoft Edge policy
      3. Removes guest session policy from the Default user hive
      4. Removes the detection sentinel
      5. Removes the staged broker files

    Every step is best-effort and continues on failure. A partially installed
    device must still be able to uninstall cleanly, and Intune reports a nonzero
    uninstall as a failed removal that it will retry forever.

    Written to work both from a command line and pasted into Intune, matching the
    install script.

.PARAMETER InstallRoot
    Where the broker was staged.

.PARAMETER KeepLogs
    Preserves the log files instead of removing the whole install root.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-LibGuestSessionBroker.ps1

.NOTES
    Author:  Oji / UMD Libraries
    Date:    2026-07-27
    Version: 0.3.0

    Exit codes: 0 always, unless the sentinel could not be removed. Detection keys
    on the sentinel, so leaving it behind would make Intune believe the app is
    still installed.

    Existing guest profiles keep the policy they were created with. Only profiles
    created after uninstall are unrestricted. On a Shared PC device the guest
    accounts rotate, so this resolves itself at the next sign-in.
#>

[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\ProgramData\LibGuestSessionBroker',

    [switch]$KeepLogs
)

begin {
    $ErrorActionPreference = 'Stop'
    $sentinelSubKey = 'SOFTWARE\UMDLibraries\LibGuestSessionBroker'
}

end {
    $transcriptLines = New-Object System.Collections.Generic.List[string]

    function Get-SentinelKey {
        <#
        .SYNOPSIS
            Opens the sentinel key in the 64-bit registry view, or returns null.
        .DESCRIPTION
            Explicitly 64-bit for the same reason as the install script: this may
            run in 32-bit PowerShell, where HKLM\SOFTWARE is redirected to
            WOW6432Node and the sentinel would appear to be absent already.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-27
            Version: 0.3.0
        #>
        [CmdletBinding()]
        param()
        process {
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine,
                [Microsoft.Win32.RegistryView]::Registry64)
            try {
                $subKey = $baseKey.OpenSubKey($sentinelSubKey)
                if ($null -eq $subKey) { return $null }
                $subKey.Dispose()
                return $sentinelSubKey
            }
            finally { $baseKey.Dispose() }
        }
    }

    function Remove-SentinelKey {
        <#
        .SYNOPSIS
            Deletes the sentinel key from the 64-bit registry view.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-27
            Version: 0.3.0
        #>
        [CmdletBinding()]
        param()
        process {
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine,
                [Microsoft.Win32.RegistryView]::Registry64)
            try {
                $baseKey.DeleteSubKeyTree($sentinelSubKey, $false)
            }
            finally { $baseKey.Dispose() }
        }
    }

    function Write-UninstallLog {
        <#
        .SYNOPSIS
            Records a line for the Intune log and, if possible, the uninstall log.
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
            $transcriptLines.Add($line)
        }
    }

    function Invoke-RemovalStep {
        <#
        .SYNOPSIS
            Runs one removal step, logging and swallowing any failure.
        .DESCRIPTION
            Uninstall must not stop at the first problem. A device that cannot
            complete removal is a device Intune retries indefinitely.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-27
            Version: 0.3.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Description,
            [Parameter(Mandatory)][scriptblock]$Action
        )
        process {
            Write-UninstallLog -Level 'INFO' -Message $Description
            try {
                & $Action
            }
            catch {
                Write-UninstallLog -Level 'WARN' -Message "  continuing after failure: $($_.Exception.Message)"
            }
        }
    }

    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $containment = Join-Path $scriptDir 'Containment'
    $powerShellExe = Join-Path $PSHOME 'powershell.exe'

    Write-UninstallLog -Level 'INFO' -Message '=== Uninstalling LibGuest session broker ==='

    Invoke-RemovalStep -Description 'Removing auto-start shortcut' -Action {
        $script = Join-Path $containment 'Install-BrokerAutoStart.ps1'
        if (Test-Path -LiteralPath $script -PathType Leaf) {
            & $powerShellExe -ExecutionPolicy Bypass -NoProfile -File $script -Remove |
                ForEach-Object { Write-UninstallLog -Level 'INFO' -Message "    $_" }
        }
        else {
            # The package may not be present, for example when uninstall is run by
            # hand. Remove the shortcut directly.
            $shortcut = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp\UMD Libraries Guest Access.lnk'
            if (Test-Path -LiteralPath $shortcut) {
                Remove-Item -LiteralPath $shortcut -Force
                Write-UninstallLog -Level 'INFO' -Message "    removed $shortcut"
            }
        }
    }

    Invoke-RemovalStep -Description 'Removing Microsoft Edge policy' -Action {
        $script = Join-Path $containment 'Set-EdgeContainmentPolicy.ps1'
        if (Test-Path -LiteralPath $script -PathType Leaf) {
            & $powerShellExe -ExecutionPolicy Bypass -NoProfile -File $script -Remove |
                ForEach-Object { Write-UninstallLog -Level 'INFO' -Message "    $_" }
        }
        else {
            $edgePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
            if (Test-Path -LiteralPath $edgePolicy) {
                Remove-Item -LiteralPath $edgePolicy -Recurse -Force
                Write-UninstallLog -Level 'INFO' -Message "    removed $edgePolicy"
            }
        }
    }

    Invoke-RemovalStep -Description 'Removing guest session policy from the Default user hive' -Action {
        $script = Join-Path $containment 'Set-GuestSessionLockdown.ps1'
        if (Test-Path -LiteralPath $script -PathType Leaf) {
            & $powerShellExe -ExecutionPolicy Bypass -NoProfile -File $script -Remove |
                ForEach-Object { Write-UninstallLog -Level 'INFO' -Message "    $_" }
        }
        else {
            Write-UninstallLog -Level 'WARN' -Message '    Set-GuestSessionLockdown.ps1 not in package; Default user policy left in place.'
        }
    }

    # Removed before the files, so a failure deleting a locked file cannot leave
    # the sentinel behind and make Intune think the app is still installed.
    $sentinelRemoved = $true
    Invoke-RemovalStep -Description "Removing detection sentinel HKLM:\$sentinelSubKey (64-bit view)" -Action {
        if (Get-SentinelKey) {
            Remove-SentinelKey
        }
    }
    if (Get-SentinelKey) {
        $sentinelRemoved = $false
        Write-UninstallLog -Level 'ERROR' -Message 'Sentinel still present. Intune will continue to report the app as installed.'
    }

    Invoke-RemovalStep -Description "Removing staged files from $InstallRoot" -Action {
        if (-not (Test-Path -LiteralPath $InstallRoot)) { return }

        if ($KeepLogs) {
            $prototype = Join-Path $InstallRoot 'Prototype'
            if (Test-Path -LiteralPath $prototype) {
                Remove-Item -LiteralPath $prototype -Recurse -Force
            }
            Write-UninstallLog -Level 'INFO' -Message "    kept logs in $InstallRoot"
        }
        else {
            # Inherited permissions restored first: the install broke inheritance,
            # and a protected ACL can block deletion.
            $acl = Get-Acl -LiteralPath $InstallRoot
            $acl.SetAccessRuleProtection($false, $true)
            Set-Acl -LiteralPath $InstallRoot -AclObject $acl
            Remove-Item -LiteralPath $InstallRoot -Recurse -Force
        }
    }

    Write-UninstallLog -Level 'INFO' -Message '=== Uninstall complete ==='

    # Best effort: if the install root survived, leave a record behind in it.
    try {
        if (Test-Path -LiteralPath $InstallRoot) {
            Add-Content -LiteralPath (Join-Path $InstallRoot 'uninstall.log') -Value $transcriptLines -Encoding UTF8
        }
    }
    catch {
        # Nothing left to write to.
    }

    if (-not $sentinelRemoved) { exit 1 }
    exit 0
}
