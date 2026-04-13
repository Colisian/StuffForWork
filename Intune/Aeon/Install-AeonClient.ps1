<#
.SYNOPSIS
    Installs the Aeon Client and removes unwanted public desktop shortcuts.
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
    $msiFile = Join-Path -Path $PSScriptRoot -ChildPath 'AeonClientInstaller_6.0.6.0.msi'
    $logFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AeonClient-Install.log"

    # Shortcuts the MSI drops that end users should not see
    $unwantedShortcuts = @(
        'Customization Manager.lnk',
        'Staff Manager.lnk'
    )
}

process {
    # --- Install the MSI ---
    if (-not (Test-Path $msiFile)) {
        Write-Error "MSI not found at $msiFile"
        exit 1
    }

    Write-Output "Installing Aeon Client from $msiFile"
    $installArgs = "/i `"$msiFile`" /qn /norestart /l*v `"$logFile`""
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArgs -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Error "msiexec exited with code $($process.ExitCode). See $logFile"
        exit $process.ExitCode
    }
    Write-Output "Aeon Client installed successfully."

    # --- Remove unwanted shortcuts ---
    $publicDesktop = 'C:\Users\Public\Desktop'

    # Poll for up to 15 seconds in case shortcuts appear after install
    $timeout = 15
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        $found = $unwantedShortcuts | Where-Object { Test-Path (Join-Path $publicDesktop $_) }
        if ($found) { break }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }

    foreach ($shortcut in $unwantedShortcuts) {
        $shortcutPath = Join-Path -Path $publicDesktop -ChildPath $shortcut
        if (Test-Path $shortcutPath) {
            Remove-Item -Path $shortcutPath -Force
            Write-Output "Removed $shortcutPath"
        }
    }
    Write-Output "Shortcut cleanup completed."
}

end {
    exit 0
}
