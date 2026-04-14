<#
.SYNOPSIS
    Copies Aeon .dbc logon files and sets the default LogonSettingsPath registry value.
.NOTES
    Author  : Oji McLeod
    Date    : 2026-04-14
    Version : 1.1
    Context : Runs as SYSTEM via Intune Win32 app. Aeon Client must be installed first (dependency).
#>

[CmdletBinding()]
param()

begin {
    $ErrorActionPreference = 'Stop'

    $destinationPath = 'C:\Program Files (x86)\Aeon'
    $sourceFolder = Join-Path -Path $PSScriptRoot -ChildPath 'Files'

    $filesToCopy = @(
        'AtlasHostingAE718.dbc',
        'AtlasHostingAE718_MDRM.dbc',
        'AtlasHostingAE718_MSPAL.dbc'
    )

    $registryPath = 'HKLM:\SOFTWARE\WOW6432Node\AtlasSystems\Aeon'
    $valueName = 'LogonSettingsPath'
    $valueData = 'C:\Program Files (x86)\Aeon\AtlasHostingAE718.dbc'
}

process {
    # --- Copy .dbc files ---
    if (-not (Test-Path -Path $destinationPath)) {
        try {
            New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
            Write-Output "Created destination folder: $destinationPath"
        }
        catch {
            Write-Error "Failed to create destination folder: $_"
            exit 1
        }
    }

    foreach ($filename in $filesToCopy) {
        $sourceFile = Join-Path -Path $sourceFolder -ChildPath $filename
        $destinationFile = Join-Path -Path $destinationPath -ChildPath $filename

        if (-not (Test-Path -Path $sourceFile)) {
            Write-Error "Source file '$filename' not found. Aborting."
            exit 1
        }

        try {
            Copy-Item -Path $sourceFile -Destination $destinationFile -Force
            Write-Output "Copied '$filename' to $destinationPath"
        }
        catch {
            Write-Error "Failed to copy '$filename': $_"
            exit 1
        }
    }

    # --- Set registry value ---
    if (-not (Test-Path $registryPath)) {
        try {
            New-Item -Path $registryPath -Force | Out-Null
            Write-Output "Created registry path: $registryPath"
        }
        catch {
            Write-Error "Failed to create registry path: $_"
            exit 1
        }
    }

    try {
        Set-ItemProperty -Path $registryPath -Name $valueName -Value $valueData -Type String -Force
        Write-Output "Registry value set: $valueName = $valueData"
    }
    catch {
        Write-Error "Failed to set registry value: $_"
        exit 1
    }

    Write-Output "Aeon Logon configuration completed."
}

end {
    exit 0
}
