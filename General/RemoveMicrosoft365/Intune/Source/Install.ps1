<#
.SYNOPSIS
    Removes consumer Microsoft 365 Click-to-Run products (O365HomePremRetail,
    OneNoteFreeRetail — all languages) using the Office Deployment Tool.

.DESCRIPTION
    Intune Win32 install wrapper. Runs non-interactively as SYSTEM.

    Logic:
      1. Reads installed C2R product IDs from the registry.
      2. Exits 0 immediately if no consumer SKUs are present (idempotent).
      3. ABORTS (exit 1) if enterprise/other C2R products coexist with the
         consumer SKUs — Remove All="TRUE" would strip those too. Such
         devices need targeted manual cleanup.
      4. Uses the ODT setup.exe bundled in the package; falls back to
         downloading the ODT bootstrapper only if the bundled copy is missing.
      5. Runs "setup.exe /configure remove.xml" and passes the exit code
         back to Intune (0 = success, 3010 = soft reboot, anything else = fail).

    Logs: C:\ProgramData\OfficeRemoval\Install.log (transcript)
          C:\ProgramData\OfficeRemoval\*.log        (ODT logging)

.NOTES
    Author  : Colisian McLeod (cmcleod1@umd.edu)
    Date    : 2026-07-14
    Version : 1.0.0
    Context : Intune Win32 app — SYSTEM, non-interactive
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$logDir = 'C:\ProgramData\OfficeRemoval'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path (Join-Path $logDir 'Install.log') -Append | Out-Null

$exitCode = 1
try {
    $consumerSkus = @('O365HomePremRetail', 'OneNoteFreeRetail')
    $c2rConfig    = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'

    # --- 1. Inventory what C2R actually has installed -----------------------
    $productIds = @()
    if (Test-Path $c2rConfig) {
        $raw = (Get-ItemProperty -Path $c2rConfig -ErrorAction SilentlyContinue).ProductReleaseIds
        if ($raw) { $productIds = $raw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } }
    }
    Write-Output "Installed C2R product IDs: $(if ($productIds) { $productIds -join ', ' } else { '<none>' })"

    $consumerPresent = @($productIds | Where-Object { $_ -in $consumerSkus })
    $otherPresent    = @($productIds | Where-Object { $_ -notin $consumerSkus })

    # --- 2. Nothing to do --------------------------------------------------
    if (-not $consumerPresent) {
        Write-Output 'No consumer Office SKUs present. Nothing to remove.'
        $exitCode = 0
        return
    }

    # --- 3. Safety guard: Remove All would also strip non-consumer products -
    if ($otherPresent) {
        Write-Warning (("Non-consumer C2R products present ({0}). Remove All=TRUE would remove them too. " +
                        'Aborting - clean this device manually with a targeted remove.xml.') -f ($otherPresent -join ', '))
        $exitCode = 1
        return
    }

    # --- 4. Stage ODT -------------------------------------------------------
    # Locate package content. With the classic command-line installer this
    # script runs from inside the extracted .intunewin, so $PSScriptRoot is
    # the content root. With the newer "PowerShell script" installer type the
    # script is materialized separately by the IME, so fall back to the
    # working directory (the app content folder).
    $contentDir = if (Test-Path (Join-Path $PSScriptRoot 'remove.xml')) { $PSScriptRoot } else { (Get-Location).Path }
    Write-Output "Package content directory: $contentDir"

    $workDir  = Join-Path $env:ProgramData 'OfficeRemoval\ODT'
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    $setupExe = Join-Path $workDir 'setup.exe'
    $bundled  = Join-Path $contentDir 'setup.exe'

    if (Test-Path $bundled) {
        Copy-Item -Path $bundled -Destination $setupExe -Force
        Write-Output 'Using ODT setup.exe bundled in the package.'
    }
    elseif (-not (Test-Path $setupExe)) {
        Write-Warning 'Bundled setup.exe not found — falling back to download (version-pinned URL).'
        $odtUrl    = 'https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_18129-20030.exe'
        $bootstrap = Join-Path $workDir 'odt.exe'
        Invoke-WebRequest -Uri $odtUrl -OutFile $bootstrap -UseBasicParsing
        Start-Process -FilePath $bootstrap -ArgumentList "/quiet /extract:`"$workDir`"" -Wait
    }

    if (-not (Test-Path $setupExe)) { throw 'ODT setup.exe unavailable after staging.' }

    $xmlPath = Join-Path $contentDir 'remove.xml'
    if (-not (Test-Path $xmlPath)) { throw "remove.xml not found at $xmlPath." }

    # --- 5. Run the removal -------------------------------------------------
    Write-Output "Running: $setupExe /configure $xmlPath"
    $proc = Start-Process -FilePath $setupExe -ArgumentList "/configure `"$xmlPath`"" -Wait -PassThru
    Write-Output "ODT exit code: $($proc.ExitCode)"

    switch ($proc.ExitCode) {
        0       { $exitCode = 0 }
        3010    { $exitCode = 3010 }   # success, soft reboot required
        default { $exitCode = $proc.ExitCode }
    }
}
catch {
    Write-Error "Removal failed: $($_.Exception.Message)"
    $exitCode = 1
}
finally {
    Stop-Transcript | Out-Null
}

exit $exitCode
