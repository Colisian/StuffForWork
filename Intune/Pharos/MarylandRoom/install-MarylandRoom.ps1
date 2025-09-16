<#  Install-MarylandRoom.ps1
    Purpose: Silent install + detection marker (no PSADT)
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---- Config ----
$AppName     = 'MarylandRoom_x64'
$ExeName     = 'LIB-MarylandRoom_for_x64.exe'
$ExeParams   = '-quiet'            # vendor-provided silent switch
$LogRoot     = Join-Path $env:ProgramData 'UMD\Logs'
$LogPath     = Join-Path $LogRoot  "$AppName.log"
$MarkerDir   = Join-Path $env:ProgramData 'UMD\Pharos'
$MarkerFile  = Join-Path $MarkerDir "$AppName.installed"
$ExePath     = Join-Path $PSScriptRoot $ExeName

# Optional: if this add-on requires Pharos Popup present, fail fast if missing
$ExpectedPopup = 'C:\Program Files (x86)\Pharos\Bin\Popup.exe'

# ---- Helpers ----
function Write-Log {
    param([string]$Message,[string]$Level='INFO')
    $stamp = (Get-Date).ToString('s')
    $line = "[$stamp][$Level] $Message"
    Write-Output $line
    Add-Content -Path $LogPath -Value $line
}

try {
    # Ensure log + marker dirs
    New-Item -ItemType Directory -Path $LogRoot  -Force | Out-Null
    New-Item -ItemType Directory -Path $MarkerDir -Force | Out-Null

    Write-Log "Starting install for $AppName"

    if (-not (Test-Path -LiteralPath $ExePath)) {
        throw "Installer not found at $ExePath"
    }

    if (-not (Test-Path -LiteralPath $ExpectedPopup)) {
        Write-Log "Warning: Expected dependency not found: $ExpectedPopup" "WARN"
        # If this should be hard-required, uncomment the next line:
        # throw "Pharos Popup prerequisite not found."
    }

    # Optional: stop Popup to avoid in-use issues
    Get-Process -Name 'Popup' -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Log "Stopping process: $($_.Name) (PID $($_.Id))"
        $_ | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    # Launch installer
    Write-Log "Executing: `"$ExePath`" $ExeParams"
    $p = Start-Process -FilePath $ExePath -ArgumentList $ExeParams -Wait -PassThru -WindowStyle Hidden

    $code = $p.ExitCode
    Write-Log "Installer exit code: $code"

    # Accept 0, 3010 (soft reboot suggested)
    if ($code -in 0,3010) {
        "Installed $(Get-Date -Format o)" | Out-File -FilePath $MarkerFile -Encoding ascii -Force
        Write-Log "Marker file written: $MarkerFile"
        if ($code -eq 3010) { Write-Log "Reboot suggested by installer (3010)" "WARN" }
        exit $code
    }
    else {
        throw "Installer returned non-success exit code: $code"
    }
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    exit 1
}
