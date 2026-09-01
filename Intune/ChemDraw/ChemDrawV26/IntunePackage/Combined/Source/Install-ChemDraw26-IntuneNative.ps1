<#
.SYNOPSIS
Installs ChemDraw 26, ChemDraw Applications 26, and performs bulk activation.

.DESCRIPTION
Designed for the Intune Win32 native PowerShell installer field or a normal
PowerShell -File command. The script locates the unpacked package by checking
for PackageMarker.txt, installs both products in the required order, activates
the completed suite, and writes a detection sentinel only after success.

.PARAMETER IncludePythonSupport
Installs the vendor-supplied Python 3.14.3 runtime for 64-bit ChemScript.

.PARAMETER ForceOffice32BitSupport
Forces the x86 Applications MSI for ChemFinder or 32-bit Office integration.

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-09-01
Version: 2.0.1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$IncludePythonSupport,
    [switch]$ForceOffice32BitSupport
)

begin {
    $ErrorActionPreference = 'Stop'
    $componentRoot = 'C:\ProgramData\UMDLibraries\ChemDraw'
    $logRoot = Join-Path $componentRoot 'Logs'
    if (-not (Test-Path -LiteralPath $logRoot)) { New-Item -Path $logRoot -ItemType Directory -Force | Out-Null }
    $logPath = Join-Path $logRoot ("Install-ChemDraw26-Combined_{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $logPath -Force | Out-Null
    $script:rebootRequired = $false

    function Resolve-PackageRoot {
        <# .SYNOPSIS Finds the unpacked Intune content directory. .NOTES Author: Oji; Date: 2026-09-01; Version: 2.0.0 #>
        [CmdletBinding()]
        param()
        $candidates = @()
        if ($PSScriptRoot) { $candidates += $PSScriptRoot }
        $candidates += (Get-Location).Path
        foreach ($candidate in @($candidates | Select-Object -Unique)) {
            if (Test-Path -LiteralPath (Join-Path $candidate 'PackageMarker.txt') -PathType Leaf) { return $candidate }
        }
        throw 'Unable to locate PackageMarker.txt in the script directory or current package directory.'
    }

    function Write-DeploymentLog {
        <# .SYNOPSIS Writes a timestamped deployment message. .NOTES Author: Oji; Date: 2026-09-01; Version: 2.0.0 #>
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$Message)
        Write-Output ("{0:u} {1}" -f (Get-Date), $Message)
    }

    function Invoke-DeploymentProcess {
        <# .SYNOPSIS Runs a deployment process and validates its exit code. .NOTES Author: Oji; Date: 2026-09-01; Version: 2.0.0 #>
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [Parameter(Mandatory)][string]$FilePath,
            [string[]]$ArgumentList = @(),
            [int[]]$SuccessCodes = @(0),
            [string]$WorkingDirectory
        )
        if (-not $WorkingDirectory) { $WorkingDirectory = $script:packageRoot }
        Write-DeploymentLog "Running: $FilePath $($ArgumentList -join ' ')"
        if (-not $PSCmdlet.ShouldProcess($FilePath, 'Run deployment process')) { return 0 }
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -Wait -PassThru -WindowStyle Hidden
        $exitCode = [int]$process.ExitCode
        Write-DeploymentLog "Exit code: $exitCode"
        if ($exitCode -in @(1641,3010)) { $script:rebootRequired = $true }
        if ($exitCode -notin $SuccessCodes) { throw "Process failed with exit code $exitCode`: $FilePath" }
        return $exitCode
    }

    function Test-MsiProduct {
        <# .SYNOPSIS Tests whether an MSI product code is installed. .NOTES Author: Oji; Date: 2026-09-01; Version: 2.0.0 #>
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$ProductCode)
        return (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode") -or
               (Test-Path -LiteralPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode")
    }

    function Get-WebView2RuntimeVersion {
        <# .SYNOPSIS Returns the installed per-machine WebView2 Runtime version. .NOTES Author: Oji; Date: 2026-09-01; Version: 2.0.1 #>
        [CmdletBinding()]
        param()
        $clientId = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
        $registryPaths = @(
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$clientId",
            "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$clientId"
        )
        foreach ($registryPath in $registryPaths) {
            $versionText = (Get-ItemProperty -LiteralPath $registryPath -Name 'pv' -ErrorAction SilentlyContinue).pv
            $parsedVersion = $null
            if ($versionText -and [version]::TryParse($versionText, [ref]$parsedVersion) -and $parsedVersion -gt [version]'0.0.0.0') {
                return $versionText
            }
        }
        return $null
    }

    function Get-IncompatibleChemDraw {
        <# .SYNOPSIS Finds installed ChemDraw products at versions 22-25. .NOTES Author: Oji; Date: 2026-09-01; Version: 2.0.0 #>
        [CmdletBinding()]
        param()
        foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
            Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
                $item = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                if ($item.DisplayName -match 'ChemDraw' -and $item.DisplayVersion -match '^(\d+)\.') {
                    $major = [int]$Matches[1]
                    if ($major -ge 22 -and $major -lt 26) {
                        $productCode = if ($_.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') { $_.PSChildName } elseif ($item.UninstallString -match '\{[0-9A-Fa-f-]{36}\}') { $Matches[0] }
                        [pscustomobject]@{ DisplayName=$item.DisplayName; DisplayVersion=$item.DisplayVersion; Major=$major; ProductCode=$productCode }
                    }
                }
            }
        }
    }

    function Test-Office32Bit {
        <# .SYNOPSIS Detects 32-bit Microsoft Office Click-to-Run. .NOTES Author: Oji; Date: 2026-09-01; Version: 2.0.0 #>
        [CmdletBinding()]
        param()
        $office = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
        return ($office.Platform -eq 'x86' -or $office.OfficeClientEdition -eq '32')
    }
}

process {
    $exitCode = 0
    try {
        $script:packageRoot = Resolve-PackageRoot
        $msiexec = Join-Path $env:WINDIR 'System32\msiexec.exe'
        $coreCode = '{C5C974CB-1827-47CC-9116-0B0C2B6903A2}'
        $apps64Code = '{39787D88-4566-4929-9C81-A086DAEB1B21}'
        $apps32Code = '{6857F9E2-AC06-471D-9777-3AB416E468CE}'
        $coreMsi = Join-Path $script:packageRoot 'Revvity\ChemDraw\Revvity_ChemDraw_26.0.0_x64.msi'
        $apps64Msi = Join-Path $script:packageRoot 'Revvity\ChemDrawApplications\Revvity_ChemDraw_Applications_26.0.0_x64.msi'
        $apps32Msi = Join-Path $script:packageRoot 'Revvity\ChemDrawApplications\Revvity_ChemDraw_Applications_26.0.0.msi'
        $dotNet = Join-Path $script:packageRoot 'ThirdParty\NETInstaller\ndp48-x86-x64-allos-enu.exe'
        $vc64 = Join-Path $script:packageRoot 'ThirdParty\Microsoft\VCRedist\vc_redist.x64.exe'
        $vc86 = Join-Path $script:packageRoot 'ThirdParty\Microsoft\VCRedist\vc_redist.x86.exe'
        $webView = Join-Path $script:packageRoot 'ThirdParty\Microsoft\WebView2\MicrosoftEdgeWebView2RuntimeInstallerX64.exe'
        $activationSource = Join-Path $script:packageRoot 'Revvity\Activation'
        $activateIni = Join-Path $activationSource 'Activate.ini'
        foreach ($required in @($coreMsi,$apps64Msi,$apps32Msi,$dotNet,$vc64,$vc86,$webView,(Join-Path $activationSource 'Activate.exe'),$activateIni)) {
            if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required package file not found: $required" }
        }
        if ((Get-Content -LiteralPath $activateIni -Raw).Trim() -notmatch '^Activation Code=[A-Z0-9]{4}(?:-[A-Z0-9]{4}){3}$') { throw 'Activate.ini is invalid.' }
        $install32Bit = $ForceOffice32BitSupport -or (Test-Office32Bit)
        if ($IncludePythonSupport -and $install32Bit) { throw 'Package 32-bit Python/pywin32 separately; the vendor does not document its silent command.' }

        foreach ($product in @(Get-IncompatibleChemDraw | Sort-Object ProductCode -Unique)) {
            if (-not $product.ProductCode) { throw "Cannot silently remove $($product.DisplayName) $($product.DisplayVersion); no MSI product code was found." }
            $oldLog = Join-Path $logRoot ("Remove-ChemDraw-{0}-{1}.log" -f $product.Major,$product.ProductCode.Trim('{}'))
            Invoke-DeploymentProcess -FilePath $msiexec -ArgumentList @('/x',$product.ProductCode,'/qn','REBOOT=ReallySuppress','/L*v',('"{0}"' -f $oldLog)) -SuccessCodes @(0,1605,1641,3010) | Out-Null
        }
        if (-not $WhatIfPreference -and @(Get-IncompatibleChemDraw).Count) { throw 'An incompatible ChemDraw 22-25 installation remains after removal.' }

        $dotNetRelease = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction SilentlyContinue).Release
        if (-not $dotNetRelease -or $dotNetRelease -lt 528040) { Invoke-DeploymentProcess -FilePath $dotNet -ArgumentList @('/q','/norestart') -SuccessCodes @(0,1641,3010) | Out-Null }
        else { Write-DeploymentLog ".NET Framework 4.8 or later is already present (Release $dotNetRelease)." }
        Invoke-DeploymentProcess -FilePath $vc86 -ArgumentList @('/q','/norestart') -SuccessCodes @(0,1638,1641,3010) | Out-Null
        Invoke-DeploymentProcess -FilePath $vc64 -ArgumentList @('/q','/norestart') -SuccessCodes @(0,1638,1641,3010) | Out-Null
        $webViewVersion = Get-WebView2RuntimeVersion
        if ($webViewVersion) {
            Write-DeploymentLog "Microsoft Edge WebView2 Runtime $webViewVersion is already installed; skipping the bundled installer."
        }
        else {
            try {
                Invoke-DeploymentProcess -FilePath $webView -ArgumentList @('/silent','/install') -SuccessCodes @(0,1641,3010) | Out-Null
            }
            catch {
                # Some Evergreen installers return a nonzero result when Edge Update completes or already owns the runtime.
                $webViewVersion = Get-WebView2RuntimeVersion
                if (-not $webViewVersion) { throw }
                Write-DeploymentLog "WebView2 installer returned a nonzero result, but runtime $webViewVersion is registered; continuing."
            }
            if (-not $webViewVersion) { $webViewVersion = Get-WebView2RuntimeVersion }
            if (-not $webViewVersion) { throw 'WebView2 installation completed without registering a valid per-machine runtime.' }
        }

        if (-not (Test-MsiProduct $coreCode)) {
            $log = Join-Path $logRoot 'Revvity_ChemDraw_26.0.0_x64.msi.log'
            Invoke-DeploymentProcess -FilePath $msiexec -ArgumentList @('/i',('"{0}"' -f $coreMsi),'ALLUSERS=1','REBOOT=ReallySuppress','/qn','/L*v',('"{0}"' -f $log)) -SuccessCodes @(0,1641,3010) | Out-Null
        } else { Write-DeploymentLog 'Main ChemDraw 26 MSI is already installed.' }

        if (-not (Test-MsiProduct $apps64Code)) {
            $log = Join-Path $logRoot 'Revvity_ChemDraw_Applications_26.0.0_x64.msi.log'
            Invoke-DeploymentProcess -FilePath $msiexec -ArgumentList @('/i',('"{0}"' -f $apps64Msi),'ALLUSERS=1','REBOOT=ReallySuppress','/qn','/L*v',('"{0}"' -f $log)) -SuccessCodes @(0,1641,3010) | Out-Null
        } else { Write-DeploymentLog 'ChemDraw Applications x64 MSI is already installed.' }

        if ($install32Bit -and -not (Test-MsiProduct $apps32Code)) {
            $log = Join-Path $logRoot 'Revvity_ChemDraw_Applications_26.0.0_x86.msi.log'
            Invoke-DeploymentProcess -FilePath $msiexec -ArgumentList @('/i',('"{0}"' -f $apps32Msi),'ALLUSERS=1','REBOOT=ReallySuppress','/qn','/L*v',('"{0}"' -f $log)) -SuccessCodes @(0,1641,3010) | Out-Null
        }

        if ($IncludePythonSupport) {
            $python = Join-Path $script:packageRoot 'ThirdParty\Python\python-3.14.3-amd64.exe'
            Invoke-DeploymentProcess -FilePath $python -ArgumentList @('/quiet','InstallAllUsers=1') -SuccessCodes @(0,1641,3010) | Out-Null
        }

        $stage = Join-Path $componentRoot 'ActivationStaging'
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
        Copy-Item -LiteralPath $activationSource -Destination $stage -Recurse -Force
        try { Invoke-DeploymentProcess -FilePath (Join-Path $stage 'Activate.exe') -ArgumentList @('26.0','IsInstaller','Silent') -WorkingDirectory $stage -SuccessCodes @(0) | Out-Null }
        finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force } }

        $sentinel = 'HKLM:\SOFTWARE\UMDLibraries\ChemDraw'
        if (-not (Test-Path -LiteralPath $sentinel)) { New-Item -Path $sentinel -Force | Out-Null }
        Set-ItemProperty -LiteralPath $sentinel -Name Version -Value '26.0.0' -Force
        Set-ItemProperty -LiteralPath $sentinel -Name CoreProductCode -Value $coreCode -Force
        Set-ItemProperty -LiteralPath $sentinel -Name ApplicationsX64ProductCode -Value $apps64Code -Force
        Set-ItemProperty -LiteralPath $sentinel -Name ActivationStatus -Value 'Activated' -Force
        Set-ItemProperty -LiteralPath $sentinel -Name ActivationDateUtc -Value ([DateTime]::UtcNow.ToString('o')) -Force
        Set-ItemProperty -LiteralPath $sentinel -Name Office32BitSupport -Value ([int]$install32Bit) -Force
        Write-DeploymentLog 'ChemDraw 26, ChemDraw Applications, and bulk activation completed successfully.'
        if ($script:rebootRequired) { $exitCode = 3010 }
    } catch {
        Write-DeploymentLog "ERROR: $($_.Exception.Message)"
        $exitCode = 1
    } finally { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null }
    exit $exitCode
}
