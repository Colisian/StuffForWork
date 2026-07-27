<#
.SYNOPSIS
    Removes the obvious ways past the LibGuest broker dialog for Shared PC guest accounts.

.DESCRIPTION
    The broker dialog runs fullscreen, topmost, and without a close button, but it
    still sits on a real desktop. Win+D minimises it, Task Manager can end it, and
    the Start menu draws above it. This script closes those routes with user
    policy.

    The target accounts are the Shared PC guest accounts, which rotate every
    session and have no Entra identity, so a user-targeted Intune profile can
    never reach them. Instead the policy is written into the Default user profile
    hive (C:\Users\Default\NTUSER.DAT), which every newly created profile inherits.

    THIS IS AN ACCOUNTABILITY GATE, NOT A SECURITY BOUNDARY. Ctrl+Alt+Del still
    reaches the Windows security screen, and a determined patron can still get to
    a desktop. That is an accepted trade: the guest account is an unprivileged,
    disposable, Shared-PC-managed account, so the cost of reaching its desktop is
    low. Choose Shell Launcher instead if that ever stops being true.

.PARAMETER Remove
    Removes the policy values this script sets, restoring default behavior for
    profiles created afterwards.

.PARAMETER DefaultProfilePath
    Override the Default user hive location.

.PARAMETER LogPath
    Override the default log location.

.EXAMPLE
    .\Set-GuestSessionLockdown.ps1

.EXAMPLE
    .\Set-GuestSessionLockdown.ps1 -Remove

.NOTES
    Author:  Oji / UMD Libraries
    Date:    2026-07-27
    Version: 0.1.0

    Requires elevation.

    AFFECTS ALL NEW PROFILES ON THE DEVICE, not only guest accounts. A first-time
    administrator sign-in on this machine would inherit the same restrictions.
    Existing profiles are untouched. On a dedicated public workstation this is
    normally acceptable; confirm before running it on a shared-purpose machine.

    Existing guest profiles do not change. Sign out and back in to pick this up,
    which is also how you should verify it.

    Deliberately NOT restricted: PowerShell. The broker prototype is a PowerShell
    script, so blocking it would break the broker. Revisit once the broker ships
    as a compiled executable.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Remove,

    [string]$DefaultProfilePath = 'C:\Users\Default\NTUSER.DAT',

    [string]$LogPath = 'C:\ProgramData\LibGuestSessionBroker\guest-lockdown.log'
)

begin {
    $ErrorActionPreference = 'Stop'
    $hiveMountPoint = 'HKLM\LibGuestDefaultProfile'
}

end {
    function Write-LockdownLog {
        <#
        .SYNOPSIS
            Appends a line to the lockdown log and echoes it.
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
                # Best effort only.
            }
        }
    }

    function Invoke-Reg {
        <#
        .SYNOPSIS
            Runs reg.exe and throws on a nonzero exit code.
        .DESCRIPTION
            reg.exe rather than the registry cmdlets on purpose. New-Item and
            Set-ItemProperty leave .NET registry handles open against a loaded
            hive, which makes the subsequent 'reg unload' fail and can leave the
            Default profile locked or damaged. reg.exe holds nothing open.
        .NOTES
            Author: Oji / UMD Libraries
            Date: 2026-07-27
            Version: 0.1.0
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string[]]$Arguments,
            [switch]$IgnoreFailure
        )
        process {
            $output = & reg.exe @Arguments 2>&1
            if ($LASTEXITCODE -ne 0 -and -not $IgnoreFailure) {
                throw "reg.exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE : $output"
            }
            return $LASTEXITCODE
        }
    }

    # Each entry: the policy subkey, the value, and what it actually stops.
    $explorerKey = 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $systemKey = 'Software\Microsoft\Windows\CurrentVersion\Policies\System'

    $policies = @(
        @{ Key = $explorerKey; Name = 'NoWinKeys';            Value = 1; Stops = 'Win+D, Win+E, Win+R and every other Win+X combination' }
        @{ Key = $explorerKey; Name = 'NoRun';                Value = 1; Stops = 'the Run command' }
        @{ Key = $explorerKey; Name = 'NoControlPanel';       Value = 1; Stops = 'Control Panel and the Settings app' }
        @{ Key = $explorerKey; Name = 'NoSetTaskbar';         Value = 1; Stops = 'taskbar and Start menu reconfiguration' }
        @{ Key = $explorerKey; Name = 'TaskbarLockAll';       Value = 1; Stops = 'unlocking or moving the taskbar' }
        @{ Key = $explorerKey; Name = 'NoTrayContextMenu';    Value = 1; Stops = 'the taskbar right-click menu, which reaches Task Manager' }
        @{ Key = $systemKey;   Name = 'DisableTaskMgr';       Value = 1; Stops = 'Task Manager, which could otherwise end the broker' }
        @{ Key = $systemKey;   Name = 'DisableRegistryTools'; Value = 1; Stops = 'regedit' }
        @{ Key = $systemKey;   Name = 'DisableCMD';           Value = 1; Stops = 'cmd.exe and batch files (PowerShell is unaffected)' }
        @{ Key = $systemKey;   Name = 'DisableChangePassword'; Value = 1; Stops = 'password change from the security screen' }
        @{ Key = $systemKey;   Name = 'DisableLockWorkstation'; Value = 1; Stops = 'Win+L, which would strand the kiosk on a lock screen' }
    )

    try {
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
        if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'This script must run elevated: it loads and writes the Default user hive.'
        }

        if (-not (Test-Path -LiteralPath $DefaultProfilePath -PathType Leaf)) {
            throw "Default user hive not found: $DefaultProfilePath"
        }

        $action = if ($Remove) { 'Removing' } else { 'Applying' }
        Write-LockdownLog -Level 'INFO' -Message "=== $action guest session lockdown ==="

        if (-not $PSCmdlet.ShouldProcess($DefaultProfilePath, "$action guest session policy")) {
            return
        }

        # A previous run that died mid-flight can leave the hive mounted.
        Invoke-Reg -Arguments @('unload', $hiveMountPoint) -IgnoreFailure | Out-Null

        Write-LockdownLog -Level 'INFO' -Message "Loading $DefaultProfilePath"
        Invoke-Reg -Arguments @('load', $hiveMountPoint, $DefaultProfilePath) | Out-Null

        try {
            foreach ($policy in $policies) {
                $fullKey = '{0}\{1}' -f $hiveMountPoint, $policy.Key

                if ($Remove) {
                    Invoke-Reg -IgnoreFailure -Arguments @(
                        'delete', $fullKey, '/v', $policy.Name, '/f'
                    ) | Out-Null
                    Write-LockdownLog -Level 'INFO' -Message ('  removed {0}' -f $policy.Name)
                }
                else {
                    Invoke-Reg -Arguments @(
                        'add', $fullKey, '/v', $policy.Name, '/t', 'REG_DWORD', '/d', $policy.Value, '/f'
                    ) | Out-Null
                    Write-LockdownLog -Level 'INFO' -Message ('  {0} = {1}  (stops {2})' -f $policy.Name, $policy.Value, $policy.Stops)
                }
            }
        }
        finally {
            # Must always run. A hive left mounted keeps the Default profile
            # locked, and the next profile creation on this device fails.
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            $unloadResult = Invoke-Reg -Arguments @('unload', $hiveMountPoint) -IgnoreFailure
            if ($unloadResult -ne 0) {
                Write-LockdownLog -Level 'ERROR' -Message "FAILED TO UNLOAD $hiveMountPoint. Run 'reg unload $hiveMountPoint' manually before creating any new profile on this device."
            }
            else {
                Write-LockdownLog -Level 'INFO' -Message 'Hive unloaded cleanly.'
            }
        }

        Write-LockdownLog -Level 'INFO' -Message "=== $action complete ==="
        Write-LockdownLog -Level 'WARN' -Message 'Existing profiles are unchanged. Sign out and start a new Guest session to verify.'
        Write-LockdownLog -Level 'WARN' -Message 'Ctrl+Alt+Del still reaches the security screen. This is an accountability gate, not a security boundary.'
    }
    catch {
        $message = "Guest session lockdown failed: $($_.Exception.Message)"
        Write-LockdownLog -Level 'ERROR' -Message $message
        [Console]::Error.WriteLine($message)
        exit 1
    }
}
