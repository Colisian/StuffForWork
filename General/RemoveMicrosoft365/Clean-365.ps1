#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes ALL Microsoft 365 Click-to-Run products (every product ID and
    language pack) from a new endpoint via the Office Deployment Tool.
.DESCRIPTION
    Intended for initial provisioning: strips preinstalled consumer Office
    (O365HomePremRetail, OneNoteFreeRetail, OEM language packs) before the
    enterprise deployment lands. Remove All="TRUE" removes EVERY C2R product,
    so the script refuses to run if an enterprise product (ProPlus / Visio /
    Project) is already installed. Exits 0 if no C2R Office is present.
.NOTES
    Author:  cmcleod1@umd.edu
    Date:    2026-07-13
    Version: 2.0
#>

$ErrorActionPreference = 'Stop'
# IWR in PS 5.1 is ~10x slower with the progress bar rendering
$ProgressPreference = 'SilentlyContinue'
$exitCode = 1

$logDir = 'C:\ProgramData\OfficeRemoval'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path (Join-Path $logDir 'Clean-365.log') -Force

$odtDir   = Join-Path $env:TEMP 'ODT'
$setupExe = Join-Path $odtDir 'setup.exe'

try {
    $c2rKey = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if (-not (Test-Path $c2rKey)) {
        Write-Host 'No Click-to-Run Office detected - nothing to remove.'
        $exitCode = 0
    } else {
        $productIds = (Get-ItemProperty -Path $c2rKey).ProductReleaseIds
        Write-Host "Installed C2R products: $productIds"

        # Remove All="TRUE" would take enterprise Office down with it
        if ($productIds -match 'ProPlus|VisioPro|ProjectPro') {
            throw "Enterprise Office product detected ($productIds); refusing to run Remove All. Scope the config to specific product IDs instead."
        }

        New-Item -ItemType Directory -Path $odtDir -Force | Out-Null

        # Remove All="TRUE" strips every C2R product AND every language pack at once
        $removeXml = @'
<Configuration>
  <Remove All="TRUE" />
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
  <Logging Level="Standard" Path="C:\ProgramData\OfficeRemoval" />
</Configuration>
'@
        $xmlPath = Join-Path $odtDir 'remove.xml'
        $removeXml | Out-File -FilePath $xmlPath -Encoding ascii -Force

        if (-not (Test-Path $setupExe)) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            # Evergreen fwlink - always redirects to the current ODT build
            $odtUrl = 'https://go.microsoft.com/fwlink/?linkid=844652'
            $bootstrap = Join-Path $odtDir 'odt.exe'
            Invoke-WebRequest -Uri $odtUrl -OutFile $bootstrap -UseBasicParsing

            $extract = Start-Process -FilePath $bootstrap -ArgumentList "/quiet /extract:`"$odtDir`"" -Wait -PassThru
            if ($extract.ExitCode -ne 0) {
                throw "ODT self-extraction failed with exit code $($extract.ExitCode)."
            }
            if (-not (Test-Path $setupExe)) {
                throw "setup.exe not found in $odtDir after extraction."
            }
        }

        $p = Start-Process -FilePath $setupExe -ArgumentList "/configure `"$xmlPath`"" -Wait -PassThru
        Write-Host "ODT exit code: $($p.ExitCode)"
        $exitCode = $p.ExitCode
    }
} catch {
    Write-Host "ERROR: $_"
    $exitCode = 1
} finally {
    Remove-Item -Path $odtDir -Recurse -Force -ErrorAction SilentlyContinue
    Stop-Transcript
}

exit $exitCode
