<#
.SYNOPSIS
    Uninstalls the Aeon Client and cleans up residual shortcuts.
.NOTES
    Author  : Oji McLeod
    Date    : 2026-04-13
    Version : 1.0
    Context : Runs as SYSTEM via Intune PowerShell deployment.
#>

[CmdletBinding()]
param()

begin {
    $ErrorActionPreference = 'Stop'
    $logFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AeonClient-Uninstall.log"
    $productName = 'Aeon Client'
}

process {
    # --- Locate the product GUID from the registry ---
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $app = Get-ItemProperty -Path $uninstallPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*$productName*" } |
        Select-Object -First 1

    if (-not $app) {
        Write-Output "$productName is not installed. Nothing to do."
        exit 0
    }

    Write-Output "Found $productName — Registry key: $($app.PSChildName)"
    Write-Output "  DisplayName    : $($app.DisplayName)"
    Write-Output "  UninstallString: $($app.UninstallString)"

    # Prefer the UninstallString from the registry; extract the GUID from it
    # Typical format: MsiExec.exe /I{GUID} or MsiExec.exe /X{GUID}
    if ($app.UninstallString -match '\{[A-F0-9\-]+\}') {
        $productGuid = $Matches[0]
    } else {
        # Fall back to the registry key name if it looks like a GUID
        $productGuid = $app.PSChildName
    }
    Write-Output "Using product GUID: $productGuid"

    $uninstallArgs = "/x `"$productGuid`" /qn /norestart /l*v `"$logFile`""
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $uninstallArgs -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Error "msiexec exited with code $($process.ExitCode). See $logFile"
        exit $process.ExitCode
    }
    Write-Output "$productName uninstalled successfully."

    # --- Clean up any leftover shortcuts from all user desktops ---
    $desktopPaths = @('C:\Users\Public\Desktop')
    $excludedProfiles = @('Public', 'Default', 'Default User', 'All Users')
    $shortcuts = @(
        'Customization Manager.lnk',
        'Staff Manager.lnk',
        'Aeon Client.lnk'
    )

    Get-ChildItem -Path 'C:\Users' -Directory |
        Where-Object { $_.Name -notin $excludedProfiles } |
        ForEach-Object { $desktopPaths += Join-Path $_.FullName 'Desktop' }

    foreach ($desktop in $desktopPaths) {
        foreach ($shortcut in $shortcuts) {
            $shortcutPath = Join-Path -Path $desktop -ChildPath $shortcut
            if (Test-Path $shortcutPath) {
                Remove-Item -Path $shortcutPath -Force
                Write-Output "Removed $shortcutPath"
            }
        }
    }
    Write-Output "Cleanup completed."
}

end {
    exit 0
}
