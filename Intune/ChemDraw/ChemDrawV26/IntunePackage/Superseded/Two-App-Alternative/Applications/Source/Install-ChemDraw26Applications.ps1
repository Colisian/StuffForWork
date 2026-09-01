<#
.SYNOPSIS
Installs ChemDraw Applications 26.0.0 and bulk-activates the completed suite.

.PARAMETER IncludeOffice32BitSupport
Forces installation of the x86 Applications MSI. It is selected automatically
when 32-bit Microsoft Office Click-to-Run is detected.

.PARAMETER IncludePythonSupport
Installs the vendor-supplied Python 3.14.3 runtime for 64-bit ChemScript.

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-09-01
Version: 1.1.0
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param([switch]$IncludeOffice32BitSupport,[switch]$IncludePythonSupport)

begin {
    $ErrorActionPreference = 'Stop'
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $componentRoot = 'C:\ProgramData\UMDLibraries\ChemDraw'
    $logRoot = Join-Path $componentRoot 'Logs'
    if (-not (Test-Path -LiteralPath $logRoot)) { New-Item -Path $logRoot -ItemType Directory -Force | Out-Null }
    $logPath = Join-Path $logRoot ("Install-ChemDraw26-Applications_{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $logPath -Force | Out-Null
    $script:rebootRequired = $false

    function Invoke-DeploymentProcess {
        <# .SYNOPSIS Runs a process and validates its exit code. .NOTES Author: Oji; Date: 2026-09-01; Version: 1.1.0 #>
        [CmdletBinding(SupportsShouldProcess = $true)]
        param([Parameter(Mandatory)][string]$FilePath,[string[]]$ArgumentList=@(),[int[]]$SuccessCodes=@(0),[string]$WorkingDirectory=$scriptDir)
        Write-Output ("{0:u} Running: {1} {2}" -f (Get-Date),$FilePath,($ArgumentList -join ' '))
        if (-not $PSCmdlet.ShouldProcess($FilePath,'Run deployment process')) { return 0 }
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -Wait -PassThru -WindowStyle Hidden
        $exitCode = [int]$process.ExitCode
        if ($exitCode -in @(1641,3010)) { $script:rebootRequired = $true }
        if ($exitCode -notin $SuccessCodes) { throw "Process failed with exit code $exitCode`: $FilePath" }
        return $exitCode
    }

    function Test-Office32Bit {
        <# .SYNOPSIS Detects 32-bit Microsoft Office Click-to-Run. .NOTES Author: Oji; Date: 2026-09-01; Version: 1.1.0 #>
        [CmdletBinding()]
        param()
        $office = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
        return ($office.Platform -eq 'x86' -or $office.OfficeClientEdition -eq '32')
    }
}

process {
    $exitCode = 0
    try {
        $sentinel = 'HKLM:\SOFTWARE\UMDLibraries\ChemDraw'
        $state = Get-ItemProperty -LiteralPath $sentinel -ErrorAction SilentlyContinue
        $coreMsiKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{C5C974CB-1827-47CC-9116-0B0C2B6903A2}'
        if ($state.CoreVersion -ne '26.0.0' -or -not (Test-Path -LiteralPath $coreMsiKey)) { throw 'Main ChemDraw 26.0.0 must be installed before ChemDraw Applications.' }

        $msiexec = Join-Path $env:WINDIR 'System32\msiexec.exe'
        $x64Msi = Join-Path $scriptDir 'Revvity\ChemDrawApplications\Revvity_ChemDraw_Applications_26.0.0_x64.msi'
        $x86Msi = Join-Path $scriptDir 'Revvity\ChemDrawApplications\Revvity_ChemDraw_Applications_26.0.0.msi'
        $vc64 = Join-Path $scriptDir 'ThirdParty\Microsoft\VCRedist\vc_redist.x64.exe'
        $vc86 = Join-Path $scriptDir 'ThirdParty\Microsoft\VCRedist\vc_redist.x86.exe'
        $webView = Join-Path $scriptDir 'ThirdParty\Microsoft\WebView2\MicrosoftEdgeWebView2RuntimeInstallerX64.exe'
        $activationSource = Join-Path $scriptDir 'Revvity\Activation'
        $activateIni = Join-Path $activationSource 'Activate.ini'
        foreach ($required in @($x64Msi,$vc64,$webView,(Join-Path $activationSource 'Activate.exe'),$activateIni)) {
            if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required package file not found: $required" }
        }
        if ((Get-Content -LiteralPath $activateIni -Raw).Trim() -notmatch '^Activation Code=[A-Z0-9]{4}(?:-[A-Z0-9]{4}){3}$') { throw 'Activate.ini is invalid.' }
        $install32Bit = $IncludeOffice32BitSupport -or (Test-Office32Bit)
        if ($IncludePythonSupport -and $install32Bit) { throw 'Package 32-bit Python/pywin32 separately; the vendor does not document its silent command.' }

        Invoke-DeploymentProcess -FilePath $vc64 -ArgumentList @('/q','/norestart') -SuccessCodes @(0,1638,1641,3010) | Out-Null
        Invoke-DeploymentProcess -FilePath $webView -ArgumentList @('/silent','/install') -SuccessCodes @(0,1641,3010) | Out-Null
        $x64Log = Join-Path $logRoot 'Revvity_ChemDraw_Applications_26.0.0_x64.msi.log'
        Invoke-DeploymentProcess -FilePath $msiexec -ArgumentList @('/i',('"{0}"' -f $x64Msi),'ALLUSERS=1','REBOOT=ReallySuppress','/qn','/L*v',('"{0}"' -f $x64Log)) -SuccessCodes @(0,1641,3010) | Out-Null

        if ($install32Bit) {
            foreach ($required in @($vc86,$x86Msi)) { if (-not (Test-Path -LiteralPath $required)) { throw "Required x86 file not found: $required" } }
            Invoke-DeploymentProcess -FilePath $vc86 -ArgumentList @('/q','/norestart') -SuccessCodes @(0,1638,1641,3010) | Out-Null
            $x86Log = Join-Path $logRoot 'Revvity_ChemDraw_Applications_26.0.0_x86.msi.log'
            Invoke-DeploymentProcess -FilePath $msiexec -ArgumentList @('/i',('"{0}"' -f $x86Msi),'ALLUSERS=1','REBOOT=ReallySuppress','/qn','/L*v',('"{0}"' -f $x86Log)) -SuccessCodes @(0,1641,3010) | Out-Null
        }
        if ($IncludePythonSupport) {
            $python = Join-Path $scriptDir 'ThirdParty\Python\python-3.14.3-amd64.exe'
            Invoke-DeploymentProcess -FilePath $python -ArgumentList @('/quiet','InstallAllUsers=1') -SuccessCodes @(0,1641,3010) | Out-Null
        }

        $stage = Join-Path $componentRoot 'ActivationStaging'
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
        Copy-Item -LiteralPath $activationSource -Destination $stage -Recurse -Force
        try { Invoke-DeploymentProcess -FilePath (Join-Path $stage 'Activate.exe') -ArgumentList @('26.0','IsInstaller','Silent') -WorkingDirectory $stage -SuccessCodes @(0) | Out-Null }
        finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force } }

        Set-ItemProperty -LiteralPath $sentinel -Name ApplicationsVersion -Value '26.0.0' -Force
        Set-ItemProperty -LiteralPath $sentinel -Name ActivationStatus -Value 'Activated' -Force
        Set-ItemProperty -LiteralPath $sentinel -Name ActivationDateUtc -Value ([DateTime]::UtcNow.ToString('o')) -Force
        Set-ItemProperty -LiteralPath $sentinel -Name Office32BitSupport -Value ([int]$install32Bit) -Force
        Write-Output 'ChemDraw Applications installed and the completed ChemDraw suite activated.'
        if ($script:rebootRequired) { $exitCode = 3010 }
    } catch { Write-Error $_.Exception.Message; $exitCode = 1 }
    finally { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null }
    exit $exitCode
}
