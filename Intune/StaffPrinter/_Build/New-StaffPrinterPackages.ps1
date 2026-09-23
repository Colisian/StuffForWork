<#
.SYNOPSIS
    Builds .intunewin packages for the staff printer apps and the driver apps.

.DESCRIPTION
    Runs IntuneWinAppUtil against every generated printer folder (any folder containing
    printer.csv) and every _Driver-* folder, writing <FolderName>.intunewin to -OutputPath.
    Printers whose master-CSV Status is not 'Ready' are skipped unless -IncludeNotReady.
    Existing packages are overwritten so a rebuild always reflects the current folder.

.PARAMETER IntuneWinAppUtil
    Path to IntuneWinAppUtil.exe (https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool).

.PARAMETER Name
    Only package these folders (e.g. 'HBK_2F_PR1','_Driver-CanonGenericPlusUFRII').

.PARAMETER OutputPath
    Default: ..\_Output (next to the printer folders; keep it out of git).

.EXAMPLE
    .\New-StaffPrinterPackages.ps1 -IntuneWinAppUtil C:\Tools\IntuneWinAppUtil.exe -Name _Driver-CanonGenericPlusUFRII, HBK_2F_PR1

.EXAMPLE
    .\New-StaffPrinterPackages.ps1 -IntuneWinAppUtil C:\Tools\IntuneWinAppUtil.exe

.NOTES
    Author:  Oji (cmcleod1@umd.edu)
    Date:    2026-09-22
    Version: 1.0.0
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$IntuneWinAppUtil,

    [string[]]$Name,

    [string]$OutputPath,

    [switch]$IncludeNotReady
)

begin {
    $ErrorActionPreference = 'Stop'
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $root = Split-Path $ScriptDir -Parent
    if (-not $OutputPath) { $OutputPath = Join-Path $root '_Output' }
    if (-not (Test-Path $OutputPath)) { New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null }

    $status = @{}
    Import-Csv (Join-Path $ScriptDir 'StaffPrinters-DirectIP.csv') | ForEach-Object { $status[$_.Name] = $_.Status }
}

process {
    $targets = Get-ChildItem -Path $root -Directory | Where-Object {
        (Test-Path (Join-Path $_.FullName 'printer.csv')) -or $_.Name -like '_Driver-*'
    }
    if ($Name) { $targets = $targets | Where-Object Name -in $Name }

    foreach ($dir in $targets) {
        $isDriver = $dir.Name -like '_Driver-*'
        $setup = if ($isDriver) { 'Install-PrinterDriver.ps1' } else { 'Install-StaffPrinter.ps1' }

        if ($isDriver -and -not (Get-ChildItem (Join-Path $dir.FullName 'Driver') -Filter *.inf -Recurse -ErrorAction SilentlyContinue)) {
            Write-Warning "$($dir.Name): no extracted driver in .\Driver - skipped."; continue
        }
        if (-not $isDriver -and $status[$dir.Name] -ne 'Ready' -and -not $IncludeNotReady) {
            Write-Warning "$($dir.Name): status '$($status[$dir.Name])' - skipped (use -IncludeNotReady)."; continue
        }
        if (-not $PSCmdlet.ShouldProcess($dir.Name, 'IntuneWinAppUtil package')) { continue }

        $final = Join-Path $OutputPath "$($dir.Name).intunewin"
        $raw   = Join-Path $OutputPath ([IO.Path]::ChangeExtension($setup, '.intunewin'))
        Remove-Item $final, $raw -Force -ErrorAction SilentlyContinue

        & $IntuneWinAppUtil -c $dir.FullName -s $setup -o $OutputPath -q | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $raw)) {
            Write-Error "$($dir.Name): IntuneWinAppUtil failed (exit $LASTEXITCODE)." -ErrorAction Continue
            continue
        }
        Move-Item $raw $final -Force
        [pscustomobject]@{
            App     = $dir.Name
            Package = $final
            SizeMB  = [math]::Round((Get-Item $final).Length / 1MB, 2)
        }
    }
}
