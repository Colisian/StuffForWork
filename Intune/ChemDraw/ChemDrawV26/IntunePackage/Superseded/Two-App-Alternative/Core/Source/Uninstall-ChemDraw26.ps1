<#
.SYNOPSIS Silently uninstalls the main ChemDraw 26.0.0 application.
.NOTES Author: Oji / University of Maryland Libraries; Date: 2026-09-01; Version: 1.1.0
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()
begin {
    $ErrorActionPreference = 'Stop'
    $componentRoot = 'C:\ProgramData\UMDLibraries\ChemDraw'
    $logRoot = Join-Path $componentRoot 'Logs'
    if (-not (Test-Path -LiteralPath $logRoot)) { New-Item -Path $logRoot -ItemType Directory -Force | Out-Null }
}
process {
    try {
        $msiexec = Join-Path $env:WINDIR 'System32\msiexec.exe'
        $msiLog = Join-Path $logRoot 'Uninstall-Revvity_ChemDraw_26.0.0_x64.msi.log'
        if ($PSCmdlet.ShouldProcess('Revvity ChemDraw 26.0.0 x64','Uninstall')) {
            $process = Start-Process -FilePath $msiexec -ArgumentList @('/x','{C5C974CB-1827-47CC-9116-0B0C2B6903A2}','/qn','REBOOT=ReallySuppress','/L*v',('"{0}"' -f $msiLog)) -Wait -PassThru -WindowStyle Hidden
            if ($process.ExitCode -notin @(0,1605,1641,3010)) { throw "Core MSI uninstall failed with exit code $($process.ExitCode)." }
        }
        $sentinel = 'HKLM:\SOFTWARE\UMDLibraries\ChemDraw'
        if (Test-Path -LiteralPath $sentinel) {
            Remove-ItemProperty -LiteralPath $sentinel -Name CoreVersion,CoreProductCode -ErrorAction SilentlyContinue
        }
        if ($process.ExitCode -in @(1641,3010)) { exit 3010 }
        exit 0
    } catch { Write-Error $_.Exception.Message; exit 1 }
}
