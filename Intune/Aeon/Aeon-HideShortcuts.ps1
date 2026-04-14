<#
.SYNOPSIS
    Removes unwanted Aeon Client shortcuts from all user desktops.
.NOTES
    Author  : Oji McLeod
    Date    : 2026-04-13
    Version : 1.1
    Context : Can run standalone as SYSTEM or from an elevated command prompt.
#>

[CmdletBinding()]
param()

begin {
    $ErrorActionPreference = 'Stop'

    $unwantedShortcuts = @(
        'Customization Manager.lnk',
        'Staff Manager.lnk'
    )
}

process {
    # --- Build list of all user desktops + public desktop ---
    $desktopPaths = @('C:\Users\Public\Desktop')
    $excludedProfiles = @('Public', 'Default', 'Default User', 'All Users')

    Get-ChildItem -Path 'C:\Users' -Directory |
        Where-Object { $_.Name -notin $excludedProfiles } |
        ForEach-Object { $desktopPaths += Join-Path $_.FullName 'Desktop' }

    # Poll for up to 15 seconds in case shortcuts appear after install
    $timeout = 15
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        $found = foreach ($desktop in $desktopPaths) {
            $unwantedShortcuts | Where-Object { Test-Path (Join-Path $desktop $_) }
        }
        if ($found) { break }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }

    foreach ($desktop in $desktopPaths) {
        foreach ($shortcut in $unwantedShortcuts) {
            $shortcutPath = Join-Path -Path $desktop -ChildPath $shortcut
            if (Test-Path $shortcutPath) {
                Remove-Item -Path $shortcutPath -Force
                Write-Output "Removed $shortcutPath"
            }
        }
    }
    Write-Output "Shortcut cleanup completed."
}

end {
    exit 0
}
