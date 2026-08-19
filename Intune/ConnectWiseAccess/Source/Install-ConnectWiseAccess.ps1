<#
.SYNOPSIS
    Silently installs the UMD Libraries ConnectWise Access agent.

.DESCRIPTION
    Installs the bundled ScreenConnect.ClientSetup.msi as a per-machine application
    under the SYSTEM account. The MSI contains the ConnectWise instance enrollment
    configuration and the McKeldin/GIS Lab organizational properties.

    The script accepts both supported Intune methods without modification:
      A) Command line: powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-ConnectWiseAccess.ps1
      B) Pasted into the Intune Win32 PowerShell script installer box.

    When pasted, PSScriptRoot is empty and Intune sets the current directory to the
    unpacked package. The script therefore falls back to the current directory when
    locating the bundled MSI.

.EXAMPLE
    .\Install-ConnectWiseAccess.ps1

    Installs or upgrades the ConnectWise Access agent silently.

.EXAMPLE
    .\Install-ConnectWiseAccess.ps1 -WhatIf

    Validates the package without installing it.

.NOTES
    Author  : Oji McLeod - ITFO / Digital Services & Technologies, UMD Libraries
    Date    : 2026-08-18
    Version : 1.0.0
    Exit    : 0 = success, 3010 = success/reboot required, 1 = failure
#>
[CmdletBinding(SupportsShouldProcess)]
param()

function Get-ConnectWiseAccessProduct {
    <#
    .SYNOPSIS
        Gets registered MSI products for the UMD Libraries ConnectWise Access agent.

    .PARAMETER DisplayName
        Exact Add/Remove Programs display name to locate.

    .NOTES
        Author  : Oji McLeod - ITFO / Digital Services & Technologies, UMD Libraries
        Date    : 2026-08-18
        Version : 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    begin {
        $ErrorActionPreference = 'Stop'
        $uninstallRoots = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )
    }

    process {
        foreach ($uninstallRoot in $uninstallRoots) {
            if (-not (Test-Path -LiteralPath $uninstallRoot)) { continue }

            Get-ChildItem -LiteralPath $uninstallRoot -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $product = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                    if ($product.DisplayName -eq $DisplayName) {
                        $product
                    }
                }
        }
    }
}

begin {
    $ErrorActionPreference = 'Stop'
    $script:result = 1
    $script:transcriptStarted = $false

    $componentRoot = 'C:\ProgramData\ConnectWiseAccess'
    if (-not (Test-Path -LiteralPath $componentRoot)) {
        New-Item -Path $componentRoot -ItemType Directory -Force | Out-Null
    }

    Start-Transcript -Path (Join-Path $componentRoot 'Install-ConnectWiseAccess.log') -Append | Out-Null
    $script:transcriptStarted = $true

    # PSScriptRoot is empty when the script is pasted into Intune.
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $installerName = 'ScreenConnect.ClientSetup.msi'
    $expectedDisplayName = 'ScreenConnect Client (f81fbe41367f771e)'
    $expectedServiceName = 'ScreenConnect Client (f81fbe41367f771e)'
    $expectedVersion = [version]'26.4.3.9662'
    $expectedSha256 = '462D1EE9994B028908A07D91613C2CDA78A83F30440A030EC50D41792B31B864'
}

process {
    try {
        Write-Output "[$(Get-Date -Format s)] ConnectWise Access installation starting."
        Write-Output "Package directory: $scriptDir"

        $installerPath = Join-Path $scriptDir $installerName
        if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
            throw "Bundled installer not found: '$installerPath'."
        }

        $actualSha256 = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
        if ($actualSha256 -ne $expectedSha256) {
            throw "Installer SHA-256 mismatch. Expected $expectedSha256 but found $actualSha256."
        }
        Write-Output "Installer integrity verified: $actualSha256"

        $registeredProducts = @(Get-ConnectWiseAccessProduct -DisplayName $expectedDisplayName)
        $installedService = Get-Service -Name $expectedServiceName -ErrorAction SilentlyContinue
        $installedVersions = @(
            $registeredProducts | ForEach-Object {
                try { [version]$_.DisplayVersion } catch { $null }
            }
        )
        $currentVersion = $installedVersions | Sort-Object -Descending | Select-Object -First 1

        if ($installedService -and $currentVersion -and $currentVersion -ge $expectedVersion) {
            Write-Output "ConnectWise Access $currentVersion is already installed; no action is required."
            $script:result = 0
            return
        }

        $nativeLog = Join-Path $componentRoot 'ConnectWiseAccess-MSI-Install.log'
        $msiArguments = @(
            '/i'
            "`"$installerPath`""
            '/qn'
            '/norestart'
            '/l*v'
            "`"$nativeLog`""
        )

        if (-not $PSCmdlet.ShouldProcess($installerPath, "Install ConnectWise Access $expectedVersion")) {
            Write-Output 'ShouldProcess declined; nothing was installed.'
            $script:result = 0
            return
        }

        $installerProcess = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArguments -Wait -PassThru
        $installerExitCode = $installerProcess.ExitCode
        Write-Output "Windows Installer exit code: $installerExitCode"

        switch ($installerExitCode) {
            0     { $script:result = 0 }
            1641  { $script:result = 3010 }
            3010  { $script:result = 3010 }
            default {
                throw "ConnectWise Access installation failed with exit code $installerExitCode. See '$nativeLog'."
            }
        }

        $registeredProducts = @(Get-ConnectWiseAccessProduct -DisplayName $expectedDisplayName)
        $installedVersions = @(
            $registeredProducts | ForEach-Object {
                try { [version]$_.DisplayVersion } catch { $null }
            }
        )
        $currentVersion = $installedVersions | Sort-Object -Descending | Select-Object -First 1
        if (-not $currentVersion -or $currentVersion -lt $expectedVersion) {
            throw "Windows Installer returned success, but version $expectedVersion or newer is not registered."
        }

        $installedService = Get-Service -Name $expectedServiceName -ErrorAction SilentlyContinue
        if (-not $installedService) {
            throw "Windows Installer returned success, but service '$expectedServiceName' was not found."
        }

        Write-Output "ConnectWise Access $currentVersion installed successfully."
        Write-Output "Service state: $($installedService.Status)"
    }
    catch {
        Write-Output "ERROR: $($_.Exception.Message)"
        Write-Output $_.ScriptStackTrace
        $script:result = 1
    }
}

end {
    Write-Output "[$(Get-Date -Format s)] Exiting with code $script:result"
    if ($script:transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
    exit $script:result
}
