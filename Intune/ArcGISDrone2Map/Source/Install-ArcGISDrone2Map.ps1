<#
.SYNOPSIS
    Silently installs ArcGIS Drone2Map 2026.1 for all users.

.DESCRIPTION
    Installs the bundled Drone2Map.msi as a per-machine application under the SYSTEM
    account. The default UMD Libraries build uses Named User licensing, allows users to
    adjust their licensing settings, disables Esri usage/error reporting, and disables
    in-app update checks so updates remain managed by Intune.

    A registry sentinel is written only after Windows Installer returns success. The
    companion Intune detection script requires both this sentinel and the MSI product
    registration, proving that this wrapper completed successfully.

    Authored for dual-method Intune use:
      A) Command line: powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-ArcGISDrone2Map.ps1
      B) Pasted into the Intune Win32 "PowerShell script installer" box (no edits required).

.PARAMETER AuthorizationType
    Sets the default licensing model. NamedUser is the UMD Libraries default. UserChoice
    omits the MSI authorization properties so the user chooses on first launch.

.PARAMETER LicenseUrl
    Optional ArcGIS Enterprise licensing portal URL. When supplied, NamedUser licensing
    is enforced for the installation. Do not place credentials or tokens in this value.

.PARAMETER EnableUsageReporting
    Enables the Esri User Experience Improvement program. Disabled by default.

.PARAMETER EnableErrorReports
    Enables automatic software error reporting to Esri. Disabled by default.

.PARAMETER EnableUpdateChecks
    Enables update checks when Drone2Map starts. Disabled by default because Intune owns
    the application update cycle.

.PARAMETER ExtraMsiProperties
    Additional public MSI properties, for example 'PORTAL_LIST="https://example.edu"'.

.EXAMPLE
    .\Install-ArcGISDrone2Map.ps1

    Installs the standard UMD Libraries per-machine Named User configuration.

.EXAMPLE
    .\Install-ArcGISDrone2Map.ps1 -LicenseUrl 'https://portal.example.edu'

    Configures an ArcGIS Enterprise portal for Named User licensing.

.NOTES
    Author  : Oji McLeod (cmcleod1@umd.edu) - ITFO / Digital Services & Technologies, UMD Libraries
    Date    : 2026-08-17
    Version : 1.0.0
    Exit    : 0 = success, 3010 = success/reboot required, 1 = failure
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('NamedUser', 'SingleUse', 'UserChoice')]
    [string]$AuthorizationType = 'NamedUser',

    [ValidatePattern('^https://')]
    [string]$LicenseUrl,

    [switch]$EnableUsageReporting,
    [switch]$EnableErrorReports,
    [switch]$EnableUpdateChecks,
    [string[]]$ExtraMsiProperties
)

begin {
    $ErrorActionPreference = 'Stop'

    $componentRoot = 'C:\ProgramData\ArcGISDrone2Map'
    if (-not (Test-Path -LiteralPath $componentRoot)) {
        New-Item -Path $componentRoot -ItemType Directory -Force | Out-Null
    }

    Start-Transcript -Path (Join-Path $componentRoot 'Install-ArcGISDrone2Map.log') -Append | Out-Null

    # $PSScriptRoot is empty when pasted into Intune, but CWD is the unpacked package.
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $sentinelPath = 'HKLM:\SOFTWARE\UMD\Intune\ArcGISDrone2Map'
    $expectedProductCode = '{E4CA5C88-DD5C-4686-8070-CF6CAC6B6FDA}'
    $packageVersion = '2026.1.0.1901'
}

process {
    try {
        Write-Output "[$(Get-Date -Format s)] ArcGIS Drone2Map installation starting."
        Write-Output "Script directory: $scriptDir"

        $msi = Get-ChildItem -LiteralPath $scriptDir -Filter 'Drone2Map.msi' -File -Recurse |
               Select-Object -First 1
        if (-not $msi) {
            throw "Drone2Map.msi was not found beneath '$scriptDir'."
        }

        Write-Output "Installer: $($msi.FullName)"
        Write-Output "Expected version: $packageVersion"

        if ($LicenseUrl -and $AuthorizationType -ne 'NamedUser') {
            throw 'LicenseUrl can only be used with AuthorizationType NamedUser.'
        }

        $msiArguments = @(
            '/i'
            "`"$($msi.FullName)`""
            '/qn'
            '/norestart'
            'ACCEPTEULA=YES'
            'ALLUSERS=1'
            "ENABLEEUEI=$(if ($EnableUsageReporting) { 1 } else { 0 })"
            "ENABLE_ERROR_REPORTS=$(if ($EnableErrorReports) { 1 } else { 0 })"
            "CHECKFORUPDATESATSTARTUP=$(if ($EnableUpdateChecks) { 1 } else { 0 })"
        )

        switch ($AuthorizationType) {
            'NamedUser' {
                $msiArguments += 'AUTHORIZATION_TYPE=NAMED_USER'
                $msiArguments += 'LOCK_AUTH_SETTINGS=FALSE'
                $msiArguments += 'ArcGIS_Connection=TRUE'
            }
            'SingleUse' {
                $msiArguments += 'AUTHORIZATION_TYPE=SINGLE_USE'
                $msiArguments += 'LOCK_AUTH_SETTINGS=FALSE'
            }
            'UserChoice' {
                Write-Output 'Authorization properties omitted; the user will choose on first launch.'
            }
        }

        if ($LicenseUrl) {
            $msiArguments += "LICENSE_URL=`"$LicenseUrl`""
        }
        if ($ExtraMsiProperties) {
            $msiArguments += $ExtraMsiProperties
        }

        $nativeLog = Join-Path $componentRoot 'Drone2Map-MSI-Install.log'
        $msiArguments += @('/l*v', "`"$nativeLog`"")

        Write-Output "Windows Installer arguments: $($msiArguments -join ' ')"

        if (-not $PSCmdlet.ShouldProcess($msi.FullName, 'Install ArcGIS Drone2Map 2026.1')) {
            Write-Output 'ShouldProcess declined; nothing was installed.'
            $script:result = 0
            return
        }

        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArguments -Wait -PassThru
        $exitCode = $process.ExitCode
        Write-Output "Windows Installer exit code: $exitCode"

        switch ($exitCode) {
            0     { $script:result = 0 }
            3010  { $script:result = 3010 }
            1641  { $script:result = 3010 }
            default {
                throw "ArcGIS Drone2Map installation failed with exit code $exitCode. See '$nativeLog'."
            }
        }

        if (-not (Test-Path -LiteralPath $sentinelPath)) {
            New-Item -Path $sentinelPath -Force | Out-Null
        }
        Set-ItemProperty -LiteralPath $sentinelPath -Name 'PackageVersion' -Value $packageVersion -Type String -Force
        Set-ItemProperty -LiteralPath $sentinelPath -Name 'ProductCode' -Value $expectedProductCode -Type String -Force
        Set-ItemProperty -LiteralPath $sentinelPath -Name 'InstallerFile' -Value $msi.Name -Type String -Force
        Set-ItemProperty -LiteralPath $sentinelPath -Name 'InstalledUtc' -Value ([DateTime]::UtcNow.ToString('o')) -Type String -Force

        Write-Output 'ArcGIS Drone2Map installation completed and the detection sentinel was written.'
    }
    catch {
        Write-Output "ERROR: $($_.Exception.Message)"
        Write-Output $_.ScriptStackTrace
        $script:result = 1
    }
}

end {
    if ($null -eq $script:result) { $script:result = 0 }
    Write-Output "[$(Get-Date -Format s)] Exiting with code $script:result"
    try { Stop-Transcript | Out-Null } catch { }
    exit $script:result
}
