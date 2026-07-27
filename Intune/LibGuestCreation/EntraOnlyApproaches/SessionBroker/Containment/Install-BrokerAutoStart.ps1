<#
.SYNOPSIS
    Registers the LibGuest session broker to start automatically at every logon.

.DESCRIPTION
    Creates a shortcut in the All Users Startup folder so the broker launches for
    every interactive logon on the device.

    Launching for every user is intentional and safe. The broker evaluates its
    session gate before creating any window: an administrator or Entra sign-in
    fails BrokerSessionAccountPattern and LocalAccount, so the process starts,
    exits silently, and shows nothing. Only a Shared PC guest session passes the
    gate and gets the dialog.

    The All Users Startup folder is used rather than an HKLM Run key to match the
    established kiosk/signage pattern on this fleet, and because it is trivial for
    staff to inspect and remove on a device that is misbehaving.

    A .ps1 cannot be placed in the Startup folder directly, so the shortcut targets
    powershell.exe with -File. The window is hidden so no console flashes behind
    the broker's fullscreen dialog.

.PARAMETER BrokerPath
    Full path to Start-LibGuestSessionBroker.ps1.

.PARAMETER Remove
    Removes the startup shortcut.

.PARAMETER LogPath
    Override the default log location.

.EXAMPLE
    .\Install-BrokerAutoStart.ps1

.EXAMPLE
    .\Install-BrokerAutoStart.ps1 -Remove

.NOTES
    Author:  Oji / UMD Libraries
    Date:    2026-07-27
    Version: 0.1.0

    Requires elevation: writes to the All Users Startup folder.

    Startup items run AFTER the shell has painted, so there is a short window at
    each guest logon where the desktop is visible before the broker covers it.
    That gap is inherent to this approach and is one of the things Shell Launcher
    would eliminate. It is accepted under the accountability-gate model.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BrokerPath = 'C:\ProgramData\LibGuestSessionBroker\Prototype\Start-LibGuestSessionBroker.ps1',

    [switch]$Remove,

    [string]$LogPath = 'C:\ProgramData\LibGuestSessionBroker\autostart.log'
)

begin {
    $ErrorActionPreference = 'Stop'
    $shortcutName = 'UMD Libraries Guest Access.lnk'
}

end {
    function Write-AutoStartLog {
        <#
        .SYNOPSIS
            Appends a line to the autostart log and echoes it.
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

    try {
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
        if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'This script must run elevated: it writes to the All Users Startup folder.'
        }

        $startupFolder = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'
        $shortcutPath = Join-Path $startupFolder $shortcutName

        if ($Remove) {
            Write-AutoStartLog -Level 'INFO' -Message '=== Removing broker auto-start ==='
            if (Test-Path -LiteralPath $shortcutPath) {
                if ($PSCmdlet.ShouldProcess($shortcutPath, 'Remove startup shortcut')) {
                    Remove-Item -LiteralPath $shortcutPath -Force
                    Write-AutoStartLog -Level 'INFO' -Message "Removed $shortcutPath"
                }
            }
            else {
                Write-AutoStartLog -Level 'INFO' -Message 'No startup shortcut present.'
            }
            return
        }

        Write-AutoStartLog -Level 'INFO' -Message '=== Installing broker auto-start ==='

        if (-not (Test-Path -LiteralPath $BrokerPath -PathType Leaf)) {
            throw "Broker script not found: $BrokerPath. Stage the Prototype folder before registering auto-start."
        }

        # Fail early rather than producing a shortcut that starts a broker which
        # immediately dies on a missing companion file.
        $brokerDirectory = Split-Path -Path $BrokerPath -Parent
        foreach ($companion in @('broker-settings.json', 'MainWindow.xaml', 'LibGuestBrokerNative.cs')) {
            $companionPath = Join-Path $brokerDirectory $companion
            if (-not (Test-Path -LiteralPath $companionPath -PathType Leaf)) {
                throw "Required companion file missing: $companionPath"
            }
        }

        if (-not (Test-Path -LiteralPath $startupFolder)) {
            throw "All Users Startup folder not found: $startupFolder"
        }

        if (-not $PSCmdlet.ShouldProcess($shortcutPath, 'Create startup shortcut')) {
            return
        }

        $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments = '-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "{0}"' -f $BrokerPath

        $shell = New-Object -ComObject WScript.Shell
        try {
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $powerShellPath
            $shortcut.Arguments = $arguments
            $shortcut.WorkingDirectory = $brokerDirectory
            $shortcut.WindowStyle = 7  # minimized
            $shortcut.Description = 'UMD Libraries guest access sign-in'
            $shortcut.Save()
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        }

        Write-AutoStartLog -Level 'INFO' -Message "Created $shortcutPath"
        Write-AutoStartLog -Level 'INFO' -Message "  target    $powerShellPath"
        Write-AutoStartLog -Level 'INFO' -Message "  arguments $arguments"
        Write-AutoStartLog -Level 'INFO' -Message '=== Installed ==='
        Write-AutoStartLog -Level 'WARN' -Message 'The broker now starts at EVERY logon. Non-guest sessions exit silently without a window.'
        Write-AutoStartLog -Level 'WARN' -Message 'Sign out and start a new Guest session to verify.'
    }
    catch {
        $message = "Broker auto-start registration failed: $($_.Exception.Message)"
        Write-AutoStartLog -Level 'ERROR' -Message $message
        [Console]::Error.WriteLine($message)
        exit 1
    }
}
