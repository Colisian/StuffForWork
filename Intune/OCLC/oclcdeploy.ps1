<#
.SYNOPSIS
    Installs OCLC Connexion client, Connexion ComService, and Microsoft Access
    Database Engine 2010 (x64), then creates a public desktop shortcut.

.DESCRIPTION
    Intune Win32 app install script. Runs non-interactively as SYSTEM.
    Checks each installer's exit code: 0 = success, 3010 = success + reboot required
    (propagated so Intune can schedule the reboot), anything else fails the install.
    Logs to C:\ProgramData\OCLC (transcript + per-MSI verbose logs).

.NOTES
    Author:  Colin McLeod
    Date:    2026-07-06
    Version: 2.0

    Exit codes: 0 = success, 1 = failure, 3010 = success (soft reboot required)
    Detection (Intune): MSI product code {106AE75F-9EFC-4721-BB06-DB6683EB8DA9}
#>

$ErrorActionPreference = 'Stop'

# Logging
$logDir = 'C:\ProgramData\OCLC'
New-Item -Path $logDir -ItemType Directory -Force | Out-Null
Start-Transcript -Path (Join-Path $logDir 'oclcdeploy.log') -Append | Out-Null

$script:rebootRequired = $false

function Invoke-Installer {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$ArgumentList,
        [Parameter(Mandatory)][string]$Name
    )
    Write-Host "Installing $Name..."
    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru
    switch ($proc.ExitCode) {
        0     { Write-Host "$Name installed successfully." }
        3010  { Write-Host "$Name installed successfully - reboot required."; $script:rebootRequired = $true }
        default {
            Write-Host "ERROR: $Name failed with exit code $($proc.ExitCode). See logs in $logDir."
            Stop-Transcript | Out-Null
            exit 1
        }
    }
}

try {
    # Installer paths (packaged alongside this script in the .intunewin)
    $connexionMsi        = Join-Path $PSScriptRoot 'Connexion.msi'
    $comServiceMsi       = Join-Path $PSScriptRoot 'OCLC.Connexion.ComServiceDeploy.msi'
    $accessDatabaseEngine = Join-Path $PSScriptRoot 'accessdatabaseengine_X64.exe'

    # Fail fast if the package is missing a source file
    foreach ($file in $connexionMsi, $comServiceMsi, $accessDatabaseEngine) {
        if (-not (Test-Path -LiteralPath $file)) {
            Write-Host "ERROR: Required installer not found: $file (packaging problem)"
            Stop-Transcript | Out-Null
            exit 1
        }
    }

    Invoke-Installer -Name 'OCLC Connexion client' -FilePath 'msiexec.exe' `
        -ArgumentList "/i `"$connexionMsi`" ALLUSERS=1 /qn /norestart /l*v `"$logDir\Connexion_install.log`""

    Invoke-Installer -Name 'OCLC Connexion ComService' -FilePath 'msiexec.exe' `
        -ArgumentList "/i `"$comServiceMsi`" ALLUSERS=1 /qn /norestart /l*v `"$logDir\ComService_install.log`""

    Invoke-Installer -Name 'Microsoft Access Database Engine 2010 (x64)' -FilePath $accessDatabaseEngine `
        -ArgumentList '/quiet /norestart'

    # Create a shortcut on the public desktop
    $targetExe    = 'C:\Program Files\OCLC\Connexion\Program\Connex.exe'
    $shortcutPath = 'C:\Users\Public\Desktop\Connexion.lnk'

    if (Test-Path -LiteralPath $targetExe) {
        $wscriptShell = New-Object -ComObject WScript.Shell
        try {
            $shortcut = $wscriptShell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath       = $targetExe
            $shortcut.WorkingDirectory = 'C:\Program Files\OCLC\Connexion\Program'
            $shortcut.WindowStyle      = 1                  # Normal window
            $shortcut.IconLocation     = "$targetExe, 0"    # Use the app's icon
            $shortcut.Save()
            Write-Host "Shortcut created successfully at $shortcutPath"
        } finally {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wscriptShell) | Out-Null
        }
    } else {
        # Installers reported success but the exe is missing - treat as failure
        Write-Host "ERROR: Executable not found at $targetExe after install."
        Stop-Transcript | Out-Null
        exit 1
    }

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Stop-Transcript | Out-Null
    exit 1
}

Write-Host 'OCLC Connexion install completed successfully.'
Stop-Transcript | Out-Null
if ($script:rebootRequired) { exit 3010 }
exit 0
