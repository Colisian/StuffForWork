<#  Detect-Mck2FloorWideFormat.ps1
    Purpose: Intune Win32 app custom detection rule for Mck2FloorWideFormat_x64

    Intune contract:
      exit 0 + STDOUT output  = DETECTED (installed)
      exit 0 + no output      = NOT detected
      non-zero exit           = NOT detected
    Configure in Intune with:
      Run script as 32-bit process on 64-bit clients : No
      Enforce script signature check                 : No
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

# ---- Config ----
# Print queue name is taken from the installer manifest inside
# LIB-Mck2FloorWideFormat_for_x64.exe (<printername> / <spoolqueuename>).
# Note the queue is "Mck2FWideFormat", NOT "Mck2FloorWideFormat".
$PrinterName  = 'LIB-Mck2FWideFormat'
$PopupExe     = 'C:\Program Files (x86)\Pharos\Bin\Popup.exe'
$MarkerFile   = Join-Path $env:ProgramData 'UMD\Pharos\Mck2FloorWideFormat_x64.installed'

# Require the marker file written by Install-Mck2FloorWideFormat.ps1 in addition
# to the queue itself. Set to $false to detect any working queue regardless of
# how it was installed.
$RequireMarker = $true

function Test-PrinterPresent {
    param([string]$Name)

    # Preferred: PrintManagement module
    $p = Get-Printer -Name $Name -ErrorAction SilentlyContinue
    if ($p) {
        # Guard against a same-named queue that is not Pharos-controlled
        if ($p.PortName -like 'Pharos*' -or $p.PortName -like 'PS[0-9]*') { return $true }
        return $false
    }

    # Fallback: raw spooler registry (module missing / Get-Printer unavailable)
    $key = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers\$Name"
    if (Test-Path -LiteralPath $key) {
        $port = (Get-ItemProperty -LiteralPath $key -Name 'Port' -ErrorAction SilentlyContinue).Port
        if ($port -like 'Pharos*' -or $port -like 'PS[0-9]*') { return $true }
    }

    return $false
}

try {
    $reasons = @()

    if (-not (Test-PrinterPresent -Name $PrinterName)) {
        $reasons += "print queue '$PrinterName' missing or not on a Pharos port"
    }

    if (-not (Test-Path -LiteralPath $PopupExe)) {
        $reasons += "Pharos Popup client missing ($PopupExe)"
    }

    if ($RequireMarker -and -not (Test-Path -LiteralPath $MarkerFile)) {
        $reasons += "marker file missing ($MarkerFile)"
    }

    if ($reasons.Count -eq 0) {
        # DETECTED - any STDOUT text plus exit 0 satisfies Intune
        Write-Output "Detected: $PrinterName present with Pharos Popup client."
        exit 0
    }

    # NOT detected - stay silent on STDOUT
    exit 1
}
catch {
    # Never report "installed" on an unexpected error
    exit 1
}
