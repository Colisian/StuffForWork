<#
.SYNOPSIS
    Removes Aeon .dbc logon files and the LogonSettingsPath registry value.
.NOTES
    Author  : Oji McLeod
    Date    : 2026-04-14
    Version : 1.0
    Context : Runs as SYSTEM via Intune Win32 app uninstall.
#>

[CmdletBinding()]
param()

begin {
    $ErrorActionPreference = 'Stop'

    $destinationPath = 'C:\Program Files (x86)\Aeon'
    $filesToRemove = @(
        'AtlasHostingAE718.dbc',
        'AtlasHostingAE718_MDRM.dbc',
        'AtlasHostingAE718_MSPAL.dbc'
    )

    $registryPath = 'HKLM:\SOFTWARE\WOW6432Node\AtlasSystems\Aeon'
    $valueName = 'LogonSettingsPath'
}

process {
    # --- Remove .dbc files ---
    foreach ($filename in $filesToRemove) {
        $filePath = Join-Path -Path $destinationPath -ChildPath $filename
        if (Test-Path $filePath) {
            Remove-Item -Path $filePath -Force
            Write-Output "Removed $filePath"
        }
    }

    # --- Remove registry value ---
    if (Test-Path $registryPath) {
        $existing = Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue
        if ($existing) {
            Remove-ItemProperty -Path $registryPath -Name $valueName -Force
            Write-Output "Removed registry value: $valueName"
        }
    }

    Write-Output "Aeon Logon configuration removed."
}

end {
    exit 0
}
