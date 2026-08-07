#requires -Version 5.1
<#
.SYNOPSIS
    Removes the Intune deployment marker. It does not undo BIOS settings.

.DESCRIPTION
    By default this script removes only HKLM\SOFTWARE\StuffForWork\DellBIOSConfig.
    It intentionally leaves the BIOS setup/admin password and all BIOS settings in
    place. To clear the setup password, an administrator must explicitly provide
    both -ClearBiosPassword and -BiosPassword. This is off by default because
    removing an administrator password weakens device security.
#>
[CmdletBinding()]
param(
    [switch]$ClearBiosPassword,
    [string]$BiosPassword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$LogRoot = Join-Path $env:ProgramData 'Dell\BIOSConfig'
$LogFile = Join-Path $LogRoot ("Uninstall-DellBIOSConfig-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$RegistryPath = 'HKLM:\SOFTWARE\StuffForWork\DellBIOSConfig'

function Write-Log {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff K'), $Level, $Message
    [System.IO.File]::AppendAllText($LogFile, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
}

function Get-CctkPath {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Dell\Command Configure\X86_64\cctk.exe'),
        (Join-Path $env:ProgramFiles 'Dell\Command Configure\X86_64\cctk.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Dell\Command Configure\cctk.exe'),
        (Join-Path $env:ProgramFiles 'Dell\Command Configure\cctk.exe')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    throw 'cctk.exe was not found; cannot clear the BIOS password.'
}

try {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Write-Log "Starting uninstall. ClearBiosPassword=$ClearBiosPassword."

    if ($ClearBiosPassword) {
        if ([string]::IsNullOrWhiteSpace($BiosPassword) -or $BiosPassword -eq 'REPLACE_WITH_YOUR_STANDARD_BIOS_PASSWORD') {
            throw 'ClearBiosPassword was requested, but no valid current BIOS password was supplied.'
        }
        if ($BiosPassword.Contains('"')) {
            throw 'The BIOS password cannot contain a double quote (") for this cctk invocation.'
        }

        if ($BiosPassword.IndexOf([char]34) -ge 0) {
            throw 'The BIOS password cannot contain a double quote for this cctk invocation.'
        }

        $cctk = Get-CctkPath
        $cctkLog = Join-Path $LogRoot ("cctk-Clear-SetupPassword-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
        $clearPasswordArgument = '--ValSetupPwd=' + [char]34 + $BiosPassword + [char]34
        $output = @(& $cctk '--SetupPwd=' $clearPasswordArgument ("-l=$cctkLog") 2>&1)
        if ($false) {
        # Dell documents this exact pattern: --SetupPwd= --ValSetupPwd=<old-password>.
        $output = @(& $cctk '--SetupPwd=' ('--ValSetupPwd="{0}"' -f $BiosPassword) ("-l=$cctkLog") 2>&1)
        }
        if ($LASTEXITCODE -ne 0) {
            throw "CCTK failed to clear the setup password (exit code $LASTEXITCODE). The deployment marker was retained."
        }
        Write-Log 'The setup/admin password was explicitly cleared at administrator request.' 'WARN'
    }
    else {
        Write-Log 'No BIOS password or BIOS settings were changed.'
    }

    if (Test-Path -LiteralPath $RegistryPath) {
        Remove-Item -LiteralPath $RegistryPath -Recurse -Force
        Write-Log 'Removed HKLM deployment marker.'
    }
    else {
        Write-Log 'Deployment marker was already absent.'
    }
    exit 0
}
catch {
    try { Write-Log "Uninstall failed: $($_.Exception.Message)" 'ERROR' } catch { }
    exit 1
}
