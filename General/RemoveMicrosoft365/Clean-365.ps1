#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes the Microsoft 365 Click-to-Run install (O365HomePremRetail +
    OneNoteFreeRetail, all languages) from a new endpoint via ODT.
#>

$ErrorActionPreference = 'Stop'
$LogDir = 'C:\ProgramData\OfficeRemoval'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$odtDir   = Join-Path $env:TEMP 'ODT'
$setupExe = Join-Path $odtDir 'setup.exe'
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
    $odtUrl = 'https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_18129-20030.exe'
    $bootstrap = Join-Path $odtDir 'odt.exe'
    Invoke-WebRequest -Uri $odtUrl -OutFile $bootstrap -UseBasicParsing
    Start-Process -FilePath $bootstrap -ArgumentList "/quiet /extract:`"$odtDir`"" -Wait
}

$p = Start-Process -FilePath $setupExe -ArgumentList "/configure `"$xmlPath`"" -Wait -PassThru
Write-Output "ODT exit code: $($p.ExitCode)"
exit $p.ExitCode