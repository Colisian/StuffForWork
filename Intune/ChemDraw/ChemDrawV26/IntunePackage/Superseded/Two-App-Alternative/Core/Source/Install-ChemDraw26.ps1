<#
.SYNOPSIS
Installs the main Revvity ChemDraw 26.0.0 application.

.DESCRIPTION
Runs as SYSTEM through Intune. Removes incompatible ChemDraw versions 22-25,
installs the prerequisites documented by the vendor installer, installs the
main ChemDraw MSI, and writes a core-install detection sentinel. Bulk activation
is intentionally performed by the dependent ChemDraw Applications package.

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-09-01
Version: 1.1.0
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()

begin {
    $ErrorActionPreference = 'Stop'
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $componentRoot = 'C:\ProgramData\UMDLibraries\ChemDraw'
    $logRoot = Join-Path $componentRoot 'Logs'
    if (-not (Test-Path -LiteralPath $logRoot)) { New-Item -Path $logRoot -ItemType Directory -Force | Out-Null }
    $logPath = Join-Path $logRoot ("Install-ChemDraw26-Core_{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $logPath -Force | Out-Null
    $script:rebootRequired = $false

    function Write-DeploymentLog {
        <# .SYNOPSIS Writes a deployment message. .NOTES Author: Oji; Date: 2026-09-01; Version: 1.1.0 #>
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$Message)
        Write-Output ("{0:u} {1}" -f (Get-Date), $Message)
    }

    function Invoke-DeploymentProcess {
        <# .SYNOPSIS Runs a process and validates its exit code. .NOTES Author: Oji; Date: 2026-09-01; Version: 1.1.0 #>
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [Parameter(Mandatory)][string]$FilePath,
            [string[]]$ArgumentList = @(),
            [int[]]$SuccessCodes = @(0)
        )
        Write-DeploymentLog "Running: $FilePath $($ArgumentList -join ' ')"
        if (-not $PSCmdlet.ShouldProcess($FilePath, 'Run deployment process')) { return 0 }
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $scriptDir -Wait -PassThru -WindowStyle Hidden
        $exitCode = [int]$process.ExitCode
        if ($exitCode -in @(1641,3010)) { $script:rebootRequired = $true }
        if ($exitCode -notin $SuccessCodes) { throw "Process failed with exit code $exitCode`: $FilePath" }
        return $exitCode
    }

    function Get-IncompatibleChemDraw {
        <# .SYNOPSIS Finds installed ChemDraw products at versions 22-25. .NOTES Author: Oji; Date: 2026-09-01; Version: 1.1.0 #>
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
}

process {
    $exitCode = 0
    try {
        $msiexec = Join-Path $env:WINDIR 'System32\msiexec.exe'
        $dotNet = Join-Path $scriptDir 'ThirdParty\NETInstaller\ndp48-x86-x64-allos-enu.exe'
        $vc64 = Join-Path $scriptDir 'ThirdParty\Microsoft\VCRedist\vc_redist.x64.exe'
        $vc86 = Join-Path $scriptDir 'ThirdParty\Microsoft\VCRedist\vc_redist.x86.exe'
        $webView = Join-Path $scriptDir 'ThirdParty\Microsoft\WebView2\MicrosoftEdgeWebView2RuntimeInstallerX64.exe'
        $coreMsi = Join-Path $scriptDir 'Revvity\ChemDraw\Revvity_ChemDraw_26.0.0_x64.msi'
        foreach ($required in @($dotNet,$vc64,$vc86,$webView,$coreMsi)) {
            if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required package file not found: $required" }
        }

        $legacy = @(Get-IncompatibleChemDraw | Sort-Object ProductCode -Unique)
        foreach ($product in $legacy) {
            if (-not $product.ProductCode) { throw "Cannot silently remove $($product.DisplayName) $($product.DisplayVersion); no MSI product code was found." }
            $oldLog = Join-Path $logRoot ("Remove-ChemDraw-{0}-{1}.log" -f $product.Major,$product.ProductCode.Trim('{}'))
            Invoke-DeploymentProcess -FilePath $msiexec -ArgumentList @('/x',$product.ProductCode,'/qn','REBOOT=ReallySuppress','/L*v',('"{0}"' -f $oldLog)) -SuccessCodes @(0,1605,1641,3010) | Out-Null
        }
        if (-not $WhatIfPreference -and @(Get-IncompatibleChemDraw).Count) { throw 'An incompatible ChemDraw 22-25 installation remains after removal.' }

        $dotNetRelease = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction SilentlyContinue).Release
        if (-not $dotNetRelease -or $dotNetRelease -lt 528040) {
            Invoke-DeploymentProcess -FilePath $dotNet -ArgumentList @('/q','/norestart') -SuccessCodes @(0,1641,3010) | Out-Null
        } else {
            Write-DeploymentLog ".NET Framework 4.8 or later is already present (Release $dotNetRelease)."
        }
        Invoke-DeploymentProcess -FilePath $vc86 -ArgumentList @('/q','/norestart') -SuccessCodes @(0,1638,1641,3010) | Out-Null
        Invoke-DeploymentProcess -FilePath $vc64 -ArgumentList @('/q','/norestart') -SuccessCodes @(0,1638,1641,3010) | Out-Null
        Invoke-DeploymentProcess -FilePath $webView -ArgumentList @('/silent','/install') -SuccessCodes @(0,1641,3010) | Out-Null
        $msiLog = Join-Path $logRoot 'Revvity_ChemDraw_26.0.0_x64.msi.log'
        Invoke-DeploymentProcess -FilePath $msiexec -ArgumentList @('/i',('"{0}"' -f $coreMsi),'ALLUSERS=1','REBOOT=ReallySuppress','/qn','/L*v',('"{0}"' -f $msiLog)) -SuccessCodes @(0,1641,3010) | Out-Null

        $sentinel = 'HKLM:\SOFTWARE\UMDLibraries\ChemDraw'
        if (-not (Test-Path -LiteralPath $sentinel)) { New-Item -Path $sentinel -Force | Out-Null }
        Set-ItemProperty -LiteralPath $sentinel -Name CoreVersion -Value '26.0.0' -Force
        Set-ItemProperty -LiteralPath $sentinel -Name CoreProductCode -Value '{C5C974CB-1827-47CC-9116-0B0C2B6903A2}' -Force
        Write-DeploymentLog 'Main ChemDraw 26 installation completed. Activation will run after ChemDraw Applications installs.'
        if ($script:rebootRequired) { $exitCode = 3010 }
    } catch {
        Write-DeploymentLog "ERROR: $($_.Exception.Message)"
        $exitCode = 1
    } finally { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null }
    exit $exitCode
}
