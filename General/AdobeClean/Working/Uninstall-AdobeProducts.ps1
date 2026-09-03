<#
.SYNOPSIS
    Uninstall-AdobeProducts.ps1
    Silently removes every installed Adobe product on a Windows device. The
    Creative Cloud desktop app (and the services it depends on) is kept by
    default; -RemoveCreativeCloud removes it too, and -CleanProgramData clears
    C:\ProgramData\Adobe.

.DESCRIPTION
    Enumerates both Uninstall hives, drops anything matching -KeepPattern,
    removes the rest per installer type (table in README). Four behaviours
    are load-bearing - do not "simplify" them; each is explained at its site:

      1. The registry UninstallString is NOT run for HD apps (it is a GUI
         launcher that exits 0 without removing anything under SYSTEM).
      2. A removal is credited ONLY when the product's Uninstall registry key
         has disappeared. Adobe exit codes are not trusted.
      3. --baseVersion is the ORIGINAL install version, not the patched
         version the registry reports (Photoshop 27.10 -> base 27.0).
      4. Creative Cloud Uninstaller.exe and AdobeCleanUpUtility.exe return 0
         in ~2 s and finish in a background child; the key is polled after.

    Runs as a file (-File .\Uninstall-AdobeProducts.ps1) and pasted into the
    Intune "PowerShell script installer" box. A pasted script gets NO command
    line - see $ForceFullRemoval in begin{} to select the mode. That box has a
    50 KB limit; check this file's size before adding prose here.

.PARAMETER LogPath
    Log directory. Default: C:\ProgramData\LIBR\Logs

.PARAMETER KeepPattern
    Regex patterns matched (case-insensitive) against DisplayName. Matching
    products are never touched. Default keeps the Creative Cloud desktop app
    and Adobe Genuine Service (CC re-installs AGS if it is removed).
    -RemoveCreativeCloud clears this default (nothing is kept) unless you pass
    -KeepPattern explicitly.

.PARAMETER RemoveUserPreferences
    Pass --deleteUserPreferences=true so per-user app settings are wiped too.

.PARAMETER RemovePackageWrappers
    Also msiexec /x the Admin Console package wrapper MSIs (DisplayVersion
    1.0.0000). WARNING: a self-service wrapper removes the CC desktop app.

.PARAMETER RemoveCreativeCloud
    Also remove the Creative Cloud desktop app, last (Adobe's uninstaller
    declines while any CC app remains). Implies -KeepPattern @() and
    -CleanProgramData unless passed explicitly. Deactivates device licensing.

.PARAMETER CleanProgramData
    Clear C:\ProgramData\Adobe (takeown + icacls, then delete). Implied by
    -RemoveCreativeCloud (-CleanProgramData:$false suppresses). Licensing
    folders are preserved while a CC desktop app is still installed.

.PARAMETER RemoveLeftoverFolders
    Delete orphaned folders under "Program Files\Adobe" and "(x86)\Adobe" that
    no remaining product owns and that do not match -KeepPattern. Never touches
    Common Files\Adobe (shared Creative Cloud runtime).

.PARAMETER AdobeUninstallerPath
    Path to AdobeUninstaller.exe. Default: <script folder>\AdobeUninstaller.exe
    if present, otherwise the per-app HDBox method is used.

.PARAMETER TimeoutMinutes
    Minutes to wait for any single uninstaller before killing it. Default: 30

.EXAMPLE
    .\Uninstall-AdobeProducts.ps1 -WhatIf
    Lists what would be removed / kept without changing anything.

.EXAMPLE
    .\Uninstall-AdobeProducts.ps1 -RemoveCreativeCloud -RemoveLeftoverFolders
    Full removal: every CC app, then the Creative Cloud desktop app, then
    C:\ProgramData\Adobe and any orphaned Program Files\Adobe folders.

.NOTES
    Author  : Oji (cmcleod1)
    Date    : 2026-09-03
    Version : 1.5.1
    Run As  : SYSTEM (Intune) or local Administrator
    PS      : 5.1+ (7.x compatible). Changelog: README-AdobeUninstall.md

    Exit codes:
      0    - All targeted products removed
      1    - Not admin, or one or more products remain
      3010 - All removed, reboot required

    Intune detection (either):
      Registry: HKLM\SOFTWARE\LIBR\AdobeUninstall  Value: Completed  DWORD = 1
      Script  : Detect-AdobeUninstall.ps1
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$LogPath = 'C:\ProgramData\LIBR\Logs',
    [string[]]$KeepPattern = @('Adobe Creative Cloud', 'Adobe Genuine Service'),
    [switch]$RemoveUserPreferences,
    [switch]$RemovePackageWrappers,
    [switch]$RemoveLeftoverFolders,
    [switch]$RemoveCreativeCloud,
    [switch]$CleanProgramData,
    [string]$AdobeUninstallerPath,
    [int]$TimeoutMinutes = 30
)

begin {
    $ErrorActionPreference = 'Stop'
    $ScriptVersion = '1.5.1'

    # Works when run as a file (PSScriptRoot set) AND when pasted into Intune (CWD = unpacked package)
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

    $SentinelKey = 'HKLM:\SOFTWARE\LIBR\AdobeUninstall'

    # PASTE DEPLOYMENTS: $true = full wipe (CC desktop app + ProgramData). Intune's
    # PowerShell script installer runs this with no command line, so it is the only way
    # to reach -RemoveCreativeCloud there. $false = remove the apps, keep Creative Cloud.
    $ForceFullRemoval = $false

    if ($ForceFullRemoval) { $RemoveCreativeCloud = [switch]$true }

    # -RemoveCreativeCloud is a full wipe: nothing is kept and ProgramData is cleared,
    # unless the caller was explicit about either.
    if ($RemoveCreativeCloud) {
        if (-not $PSBoundParameters.ContainsKey('KeepPattern'))     { $KeepPattern = @() }
        if (-not $PSBoundParameters.ContainsKey('CleanProgramData')) { $CleanProgramData = $true }
    }

    # Registry entries belonging to the CC desktop app itself. Handled in their own step
    # (after every CC app) rather than by the generic MSI/EXE steps.
    $CreativeCloudPattern = '^Adobe Creative Cloud'

    # Children of C:\ProgramData\Adobe holding licensing/activation state. Deleting these
    # deactivates a Creative Cloud install, so they survive -CleanProgramData whenever the
    # desktop app is being kept.
    $ProgramDataLicensingChild = @(
        'SLStore', 'SLCache', 'Adobe PCD', 'UPI',               # named-user activation
        'OperatingConfigs', 'LicensingToolkit',                 # Shared Device / Feature Restricted Licensing
        'AAMUpdater', 'OOBE', 'caps', 'Adobe Desktop Common', 'ARM', 'Adobe Notification Client'
    )

    # Base versions confirmed on real devices, tried first. Rolling-train apps keep their
    # original base for years, so it is not derivable (Lightroom needed 22 sweep attempts).
    $KnownBaseVersion = @{
        'LRCC' = '1.0'      # Lightroom - ships 9.x, base 1.0. Confirmed 2026-09-01, LIBRWKSPC010189
    }

    # Creative Cloud runtime that lives under Program Files\Adobe and must never be
    # killed or deleted while CC is kept (CoreSync = CC file sync, CCX = CC Experience).
    $ProtectedPathPattern = @(
        'Adobe Creative Cloud',
        'Creative Cloud Experience',
        'Adobe Sync',
        'Adobe Desktop Common',
        'AdobeGCClient',
        '\\Adobe\\Common$'     # Program Files\Adobe\Common - shared runtime, not a product folder
    )
    $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $LogFile = Join-Path $LogPath "AdobeUninstall-$Timestamp.log"
    $TimeoutSeconds = $TimeoutMinutes * 60

    $script:startTime = Get-Date
    $script:rebootRequired = $false
    $script:protectCcPaths = $true    # released once the CC desktop app is confirmed gone
    $script:ccRemoved = $false
    $script:removed = [System.Collections.Generic.List[string]]::new()
    $script:failed = [System.Collections.Generic.List[string]]::new()
    $script:skippedLegacy = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force -WhatIf:$false | Out-Null }

    function Write-Log {
        param(
            [string]$Message,
            [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
            [string]$Level = 'INFO'
        )
        $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
        Add-Content -Path $LogFile -Value $entry -WhatIf:$false   # logging is never a WhatIf-able change
        switch ($Level) {
            'ERROR'   { Write-Host $entry -ForegroundColor Red }
            'WARN'    { Write-Host $entry -ForegroundColor Yellow }
            'SUCCESS' { Write-Host $entry -ForegroundColor Green }
            default   { Write-Host $entry }
        }
    }

    function Test-Keep {
        param([string]$Name)
        foreach ($p in $KeepPattern) { if ($Name -match $p) { return $true } }
        return $false
    }

    function Test-ProtectedPath {
        # Keep patterns + built-in CC runtime folders; used for processes and leftover folders
        param([string]$Path)
        if (Test-Keep -Name $Path) { return $true }
        if (-not $script:protectCcPaths) { return $false }
        foreach ($p in $ProtectedPathPattern) { if ($Path -match $p) { return $true } }
        return $false
    }

    function Get-AdobeProduct {
        <# Enumerates Adobe entries from both Uninstall hives and classifies them.
           Never uses Win32_Product (it triggers MSI self-repair on every product). #>
        $hives = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        Get-ItemProperty $hives -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -and
                ($_.Publisher -match '^Adobe' -or $_.DisplayName -match '^Adobe\b')
            } |
            ForEach-Object {
                $us = [string]$_.UninstallString
                $qs = [string]$_.QuietUninstallString
                $type =
                    if ($us -match 'PDApp\.exe') { 'Legacy' }
                    elseif ($us -match '--sapCode=' -or $us -match '\\HDBox\\') { 'HD' }
                    elseif (($_.WindowsInstaller -eq 1 -or $us -match '^\s*msiexec') -and
                            [string]$_.DisplayVersion -eq '1.0.0000') { 'Package' }   # Admin Console package wrapper
                    elseif ($_.WindowsInstaller -eq 1 -or $us -match '^\s*msiexec') { 'MSI' }
                    else { 'EXE' }

                $sap = $null; $base = $null; $plat = 'win64'
                if ($type -eq 'HD') {
                    if ($us -match '--sapCode=(\S+)') { $sap = $Matches[1] }
                    if ($us -match '--(?:baseVersion|productVersion)=(\S+)') { $base = $Matches[1] }
                    if ($us -match '--(?:platform|productPlatform)=(\S+)') { $plat = $Matches[1] }
                }

                [pscustomobject]@{
                    Name            = $_.DisplayName
                    Version         = $_.DisplayVersion
                    Publisher       = $_.Publisher
                    Key             = $_.PSPath
                    ProductCode     = $_.PSChildName
                    Type            = $type
                    UninstallString = $us
                    QuietUninstall  = $qs
                    InstallLocation = $_.InstallLocation
                    SapCode         = $sap
                    BaseVersion     = $base
                    Platform        = $plat
                    Keep            = (Test-Keep -Name $_.DisplayName)
                }
            } | Sort-Object Name -Unique
    }

    function Invoke-Uninstaller {
        <# Runs an uninstaller with a hard timeout. Returns exit code, or -1 on timeout/launch failure. #>
        param(
            [Parameter(Mandatory)][string]$FilePath,
            [string]$ArgumentList = '',
            [Parameter(Mandatory)][string]$Label
        )
        if (-not (Test-Path -LiteralPath $FilePath)) {
            Write-Log "Uninstaller not found for ${Label}: $FilePath" -Level WARN
            return -1
        }
        Write-Log "Running: `"$FilePath`" $ArgumentList"
        try {
            $psi = @{ FilePath = $FilePath; PassThru = $true; NoNewWindow = $true }
            if ($ArgumentList) { $psi.ArgumentList = $ArgumentList }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $proc = Start-Process @psi
            $null = $proc.Handle   # cache the handle, otherwise ExitCode is $null after WaitForExit(timeout)
            if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
                Write-Log "TIMEOUT after $TimeoutMinutes min - killing $Label (PID $($proc.Id))" -Level ERROR
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                return -1
            }
            $exit = if ($null -ne $proc.ExitCode) { [int]$proc.ExitCode } else { -1 }
            Write-Log ("  exit {0} after {1:n0} s" -f $exit, $sw.Elapsed.TotalSeconds)
            return $exit
        }
        catch {
            Write-Log "Failed to launch uninstaller for ${Label}: $_" -Level ERROR
            return -1
        }
    }

    function Split-CommandLine {
        <# Splits '"C:\path\app.exe" --a --b' or 'C:\path\app.exe /x' into exe + args #>
        param([string]$CommandLine)
        $cl = $CommandLine.Trim()
        if ($cl -match '^"(?<exe>[^"]+)"\s*(?<args>.*)$') { return @($Matches.exe, $Matches.args) }
        if ($cl -match '^(?<exe>.+?\.exe)\s*(?<args>.*)$')  { return @($Matches.exe, $Matches.args) }
        return @($cl, '')
    }

    function Get-BaseVersionFromJson {
        <# application.json carries the real BaseVersion (Adobe points admins at
           Build\HD\<sap>\Application.json). Search bounded to 3 levels to stay fast. #>
        param([string]$InstallLocation, [string]$SapCode, [string]$ProductName)

        # Roots: InstallLocation (often EMPTY for HD apps), Program Files\Adobe folders
        # matching the product name, then the per-sapCode HD staging areas.
        $roots = [System.Collections.Generic.List[string]]::new()
        if ($InstallLocation -and (Test-Path -LiteralPath $InstallLocation)) { $roots.Add($InstallLocation) }

        if ($ProductName) {
            # "Adobe Bridge 2026" -> match folders starting "Adobe Bridge"
            $stem = ($ProductName -replace '\s+\d{4}$', '').Trim()
            foreach ($base in @("$env:ProgramFiles\Adobe", "${env:ProgramFiles(x86)}\Adobe")) {
                if (-not (Test-Path -LiteralPath $base)) { continue }
                Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "$stem*" } |
                    ForEach-Object { $roots.Add($_.FullName) }
            }
        }
        if ($SapCode) {
            foreach ($hd in @(
                "${env:ProgramFiles(x86)}\Common Files\Adobe\Installers\$SapCode",
                "$env:ProgramData\Adobe\HDBox\$SapCode",
                "${env:ProgramFiles(x86)}\Common Files\Adobe\caps\$SapCode"
            )) { if (Test-Path -LiteralPath $hd) { $roots.Add($hd) } }
        }

        foreach ($root in ($roots | Select-Object -Unique)) {
            try {
                foreach ($json in (Get-ChildItem -LiteralPath $root -Filter 'application.json' -Recurse -Depth 3 -File -ErrorAction SilentlyContinue)) {
                    $raw = Get-Content -LiteralPath $json.FullName -Raw -ErrorAction SilentlyContinue
                    if (-not $raw) { continue }
                    # Only trust a file that also names this sapCode, when we know it
                    if ($SapCode -and $raw -notmatch [regex]::Escape($SapCode)) { continue }
                    # Property casing varies across builds (BaseVersion / baseVersion)
                    if ($raw -match '"[Bb]ase[Vv]ersion"\s*:\s*"([^"]+)"') {
                        Write-Log "  baseVersion $($Matches[1]) from $($json.FullName)"
                        return $Matches[1]
                    }
                }
            }
            catch { }
        }
        return $null
    }

    function Get-BaseVersionCandidate {
        <# HD's --baseVersion is the version of the ORIGINAL install, not the current
           (updated) version the registry reports. Photoshop 27.10 -> base 27.0.
           Most apps use major.0; a few (Lightroom, Rush, UXP) may use major.minor.
           Wrong guesses are declined by the engine in ~1 s with exit 135, so try a few. #>
        param([string]$Version, [string]$Known, [int]$MaxCandidates = 48)
        $parts = $Version.Split('.')
        $maj = $parts[0]
        $majVal = 0; $majOk = [int]::TryParse($maj, [ref]$majVal)
        $minVal = 0; $minOk = ($parts.Count -ge 2) -and [int]::TryParse($parts[1], [ref]$minVal)

        $c = [System.Collections.Generic.List[string]]::new()
        if ($Known) { $c.Add($Known) }                                   # application.json - authoritative
        $c.Add("$maj.0")                                                 # 27.0    most common form
        $c.Add("$maj.0.0")                                               # 16.0.0  Adobe also publishes 3-part bases
        $c.Add($Version)                                                 # 27.10   exact (never-updated apps)
        if ($parts.Count -ge 2) {
            $c.Add("$maj.$($parts[1])")                                  # 9.5
            $c.Add("$maj.$($parts[1]).0")                                # 9.5.0
        }
        # Walk minors down inside the installed major
        if ($minOk) { for ($m = $minVal - 1; $m -ge 0; $m--) { $c.Add("$maj.$m") } }

        # Walk MAJORS down: rolling-train apps (Bridge, Lightroom) keep the base of their
        # original release for years (Adobe documents Bridge as 12.0.0). ~1 s per miss.
        if ($majOk) {
            for ($M = $majVal - 1; $M -ge 1; $M--) { $c.Add("$M.0"); $c.Add("$M.0.0") }
        }
        return @($c | Where-Object { $_ } | Select-Object -Unique | Select-Object -First $MaxCandidates)
    }

    function Register-Result {
        <# Credits a removal ONLY if the Uninstall key is gone - Adobe launchers exit 0 doing
           nothing. Creative Cloud Uninstaller.exe -u and AdobeCleanUpUtility.exe return 0 in
           ~2 s and finish in a background child, so -GraceSeconds polls the key first and
           -WaitProcess waits for that child. #>
        param([string]$Name, [string]$Key, [int]$Code, [int[]]$NotInstalledCodes = @(),
              [int]$GraceSeconds = 0, [string]$WaitProcess)
        $stillRegistered = if ($Key) { Test-Path $Key } else { $false }
        if ($stillRegistered -and $GraceSeconds -gt 0) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt $GraceSeconds) {
                Start-Sleep -Seconds 3
                $busy = $WaitProcess -and (Get-Process -Name $WaitProcess -ErrorAction SilentlyContinue)
                if (-not (Test-Path $Key)) { $stillRegistered = $false; break }
                if (-not $busy -and $sw.Elapsed.TotalSeconds -ge 15) { break }   # child gone, key still there: it declined
            }
            Write-Log ("  waited {0:n0} s for background uninstall - key {1}" -f $sw.Elapsed.TotalSeconds, $(if ($stillRegistered) { 'still present' } else { 'gone' }))
        }

        if ($stillRegistered) {
            $why = switch ($Code) {
                0       { 'exit 0 but Uninstall key still present - uninstaller was a launcher/handoff or silently declined' }
                135     { 'exit 135 (HD engine: product/baseVersion not installed) - no baseVersion candidate matched' }
                105     { 'exit 105 (HD engine: insufficient privileges)' }
                -1      { 'launch failed, timed out, or exit code unavailable' }
                default { "exit $Code and Uninstall key still present" }
            }
            Write-Log "FAILED: $Name - $why" -Level ERROR
            $script:failed.Add("$Name (exit $Code)")
            return
        }
        if ($Code -eq 3010 -or $Code -eq 1641) {
            Write-Log "Removed: $Name (reboot required)" -Level WARN
            $script:removed.Add($Name); $script:rebootRequired = $true
        }
        elseif ($Code -in $NotInstalledCodes) {
            Write-Log "Removed: $Name (uninstaller reported not installed, exit $Code)" -Level WARN
            $script:removed.Add($Name)
        }
        elseif ($Code -eq 0) {
            Write-Log "Removed: $Name" -Level SUCCESS; $script:removed.Add($Name)
        }
        else {
            Write-Log "Removed: $Name (registry entry gone, but exit code was $Code)" -Level WARN
            $script:removed.Add($Name)
        }
    }
}

process {
    Write-Log '=============================================='
    Write-Log "LIBR Adobe Product Uninstall v$ScriptVersion"
    Write-Log "Computer : $env:COMPUTERNAME   User: $env:USERNAME   Host: $(if ([Environment]::Is64BitProcess) { '64-bit' } else { '32-bit' }) PS $($PSVersionTable.PSVersion)"
    Write-Log "Keep     : $(if ($KeepPattern.Count) { $KeepPattern -join ' | ' } else { '(nothing - full Adobe removal)' })"
    Write-Log "Options  : RemoveUserPreferences=$RemoveUserPreferences RemovePackageWrappers=$RemovePackageWrappers RemoveLeftoverFolders=$RemoveLeftoverFolders WhatIf=$WhatIfPreference"
    Write-Log "Full wipe: RemoveCreativeCloud=$RemoveCreativeCloud CleanProgramData=$CleanProgramData" -Level $(if ($RemoveCreativeCloud) { 'WARN' } else { 'INFO' })
    Write-Log "Timeout  : $TimeoutMinutes min per uninstaller"
    Write-Log '=============================================='

    # ---------------------------------------------------------------- Pre-flight
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { Write-Log 'Must run as Administrator or SYSTEM. Exiting.' -Level ERROR; exit 1 }

    # A 32-bit host on a 64-bit OS is redirected to the WOW6432Node hive and cannot see
    # 64-bit-only products - they would be silently skipped and never counted as remaining.
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Write-Log 'Running in a 32-bit PowerShell host on 64-bit Windows: 64-bit Adobe products would be invisible. Relaunch via %windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe (Intune: Run as 32-bit = No). Exiting.' -Level ERROR
        exit 1
    }

    # ---------------------------------------------------------------- Inventory
    Write-Log '--- STEP 1: Inventory ---'
    $inventory = @(Get-AdobeProduct)
    if ($inventory.Count -eq 0) {
        Write-Log 'No Adobe products found.' -Level SUCCESS
    }
    $wrappers = @($inventory | Where-Object { -not $_.Keep -and $_.Type -eq 'Package' })
    $targets = @($inventory | Where-Object { -not $_.Keep -and ($_.Type -ne 'Package' -or $RemovePackageWrappers) })
    $targetNames = @($targets.Name)

    foreach ($p in $inventory) {
        $tag =
            if ($p.Keep)                    { 'KEEP  ' }
            elseif ($p.Name -in $targetNames) { 'REMOVE' }
            else                            { 'SKIP  ' }   # package wrapper, not targeted
        Write-Log ("[{0}] [{1,-7}] {2} {3}" -f $tag, $p.Type, $p.Name, $p.Version)
    }
    if ($wrappers.Count -gt 0 -and -not $RemovePackageWrappers) {
        Write-Log "Skipping $($wrappers.Count) Admin Console package wrapper(s) (use -RemovePackageWrappers to include): $($wrappers.Name -join '; ')" -Level WARN
    }
    Write-Log "Targets: $($targets.Count)   Kept: $(@($inventory | Where-Object Keep).Count)"

    if ($targets.Count -gt 0) {

        # ------------------------------------------------------------ Stop processes
        # Kill anything running from Program Files\Adobe\* that is not Creative Cloud.
        # Creative Cloud runtime lives in Common Files\Adobe and Program Files\Adobe\Adobe Creative Cloud*,
        # so it is left running by design (the HD uninstaller does not need it stopped) - even
        # under -RemoveCreativeCloud, where STEP 6 stops it once the apps are gone.
        Write-Log '--- STEP 2: Stopping Adobe application processes ---'
        $adobeRoots = @("$env:ProgramFiles\Adobe\", "${env:ProgramFiles(x86)}\Adobe\")
        $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $path = $_.Path
            $path -and
            ($adobeRoots | Where-Object { $path.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }) -and
            -not (Test-ProtectedPath -Path $path)
        }
        foreach ($proc in $procs) {
            if ($PSCmdlet.ShouldProcess("$($proc.ProcessName) (PID $($proc.Id))", 'Stop process')) {
                try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop; Write-Log "Stopped: $($proc.ProcessName) (PID $($proc.Id))" }
                catch {
                    if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) { Write-Log "Could not stop $($proc.ProcessName): $_" -Level WARN }
                    else { Write-Log "  $($proc.ProcessName) (PID $($proc.Id)) already exited" }
                }
            }
        }
        if (-not $procs) { Write-Log 'No Adobe application processes running.' }
        # Acrobat updater service holds locks on Acrobat files
        $arm = Get-Service -Name 'AdobeARMservice' -ErrorAction SilentlyContinue
        if ($arm -and $arm.Status -eq 'Running' -and $PSCmdlet.ShouldProcess('AdobeARMservice', 'Stop service')) {
            try { Stop-Service -Name 'AdobeARMservice' -Force -ErrorAction Stop; Write-Log 'Stopped AdobeARMservice' }
            catch { Write-Log "Could not stop AdobeARMservice: $_" -Level WARN }
        }
        Start-Sleep -Seconds 2

        # ------------------------------------------------------------ 3a. Creative Cloud apps (bulk)
        Write-Log '--- STEP 3: Creative Cloud (HyperDrive) apps ---'
        $hdTargets = @($targets | Where-Object { $_.Type -eq 'HD' -and $_.SapCode -and $_.BaseVersion })

        if (-not $AdobeUninstallerPath) { $AdobeUninstallerPath = Join-Path $ScriptDir 'AdobeUninstaller.exe' }
        if ($hdTargets.Count -gt 0 -and (Test-Path -LiteralPath $AdobeUninstallerPath)) {
            $productArg = ($hdTargets | ForEach-Object { "$($_.SapCode)#$($_.BaseVersion)" }) -join ','
            $prefArg = if ($RemoveUserPreferences) { ' --deleteUserPreferences' } else { '' }
            if ($PSCmdlet.ShouldProcess($productArg, 'AdobeUninstaller.exe bulk uninstall')) {
                $code = Invoke-Uninstaller -FilePath $AdobeUninstallerPath `
                    -ArgumentList "--products=$productArg --skipNotInstalled$prefArg" -Label 'AdobeUninstaller.exe'
                Write-Log "AdobeUninstaller.exe exit code: $code"
                # Re-inventory: whatever is gone is credited, remainder falls through to per-app
                $stillThere = @(Get-AdobeProduct | Where-Object { -not $_.Keep -and $_.Type -eq 'HD' })
                foreach ($h in $hdTargets) {
                    if ($h.Name -notin $stillThere.Name) { Write-Log "Removed: $($h.Name)" -Level SUCCESS; $script:removed.Add($h.Name) }
                }
                $hdTargets = $stillThere
            }
        }
        elseif ($hdTargets.Count -gt 0) {
            Write-Log "AdobeUninstaller.exe not found at $AdobeUninstallerPath - using per-app HDBox uninstaller."
        }

        # ------------------------------------------------------------ 3b. Creative Cloud apps (per-app)
        # The registry UninstallString is deliberately NOT used: on current builds it is
        # HDBox\Uninstaller.exe --mode=2, a launcher that hands off to the CC desktop app
        # (sign-in prompt), exits 0 after ~2 s and removes nothing under SYSTEM.
        # HDBox ships BOTH Setup.exe (~850 KB, the HD engine) and Set-up.exe (~14 MB, the CC
        # installer bootstrapper); Setup.exe is the one we want, Set-up.exe a last resort.
        $hdSetup = @(
            "${env:ProgramFiles(x86)}\Common Files\Adobe\Adobe Desktop Common\HDBox\Setup.exe",
            "$env:ProgramFiles\Common Files\Adobe\Adobe Desktop Common\HDBox\Setup.exe",
            "${env:ProgramFiles(x86)}\Common Files\Adobe\Adobe Desktop Common\HDBox\Set-up.exe",
            "$env:ProgramFiles\Common Files\Adobe\Adobe Desktop Common\HDBox\Set-up.exe"
        ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

        $hdAll = @($targets | Where-Object { $_.Type -eq 'HD' })
        if ($hdAll.Count -gt 0) {
            if ($hdSetup) { Write-Log "HD silent engine: $hdSetup" }
            else { Write-Log 'HDBox Set-up.exe/Setup.exe NOT found - will fall back to registry UninstallString (likely a GUI launcher; expect failures)' -Level WARN }
        }
        $prefValue = if ($RemoveUserPreferences) { 'true' } else { 'false' }

        foreach ($p in $hdAll) {
            if ($p.Name -in $script:removed) { continue }
            if (-not (Test-Path $p.Key)) {
                # Shared components (e.g. UXP WebView Support) go with the last app that needed them
                Write-Log "Removed: $($p.Name) (went with an earlier uninstall)" -Level SUCCESS
                $script:removed.Add($p.Name)
                continue
            }

            if ($hdSetup -and $p.SapCode -and $p.BaseVersion) {
                # Try each baseVersion candidate until the Uninstall key disappears
                if ($PSCmdlet.ShouldProcess($p.Name, 'Uninstall (HDBox engine)')) {
                    $known = Get-BaseVersionFromJson -InstallLocation $p.InstallLocation -SapCode $p.SapCode -ProductName $p.Name
                    if (-not $known -and $KnownBaseVersion.ContainsKey($p.SapCode)) {
                        $known = $KnownBaseVersion[$p.SapCode]
                        Write-Log "  baseVersion $known from known-product table ($($p.SapCode))"
                    }
                    $code = -1
                    $recognized = [System.Collections.Generic.List[string]]::new()
                    foreach ($bv in (Get-BaseVersionCandidate -Version $p.BaseVersion -Known $known)) {
                        $uArgs = "--uninstall=1 --sapCode=$($p.SapCode) --baseVersion=$bv --platform=$($p.Platform) --deleteUserPreferences=$prefValue"
                        $code = Invoke-Uninstaller -FilePath $hdSetup -ArgumentList $uArgs -Label $p.Name
                        if (-not (Test-Path $p.Key)) {
                            Write-Log "  baseVersion $bv accepted"
                            break
                        }
                        if ($code -eq 135) {
                            Write-Log "  baseVersion $bv declined (135 = not installed) - trying next candidate" -Level WARN
                        }
                        else {
                            # Not 135: the engine recognised this baseVersion and then failed.
                            # That is the value to investigate in Adobe's installer logs.
                            Write-Log "  baseVersion $bv RECOGNISED but uninstall failed (exit $code) - continuing sweep" -Level ERROR
                            $recognized.Add("$bv (exit $code)")
                        }
                    }
                    if ((Test-Path $p.Key) -and $recognized.Count -gt 0) {
                        Write-Log "  $($p.SapCode): engine accepted baseVersion(s) $($recognized -join ', ') but could not complete. Check Adobe installer logs under '${env:ProgramFiles(x86)}\Common Files\Adobe\Installers' and %TEMP%." -Level ERROR
                    }
                    Register-Result -Name $p.Name -Key $p.Key -Code $code -NotInstalledCodes @(135)
                }
                continue
            }
            elseif ($p.UninstallString) {
                Write-Log "$($p.Name): using registry UninstallString as last resort" -Level WARN
                $uExe, $uArgs = Split-CommandLine $p.UninstallString
                if ($uArgs -match '--deleteUserPreferences=') {
                    $uArgs = $uArgs -replace '--deleteUserPreferences=\S+', "--deleteUserPreferences=$prefValue"
                } else {
                    $uArgs = "$uArgs --deleteUserPreferences=$prefValue".Trim()
                }
            }
            else { Write-Log "$($p.Name): no UninstallString and no HD engine" -Level ERROR; $script:failed.Add($p.Name); continue }

            if ($PSCmdlet.ShouldProcess($p.Name, 'Uninstall (HDBox)')) {
                $code = Invoke-Uninstaller -FilePath $uExe -ArgumentList $uArgs -Label $p.Name
                # 135 = not installed; 105 = insufficient privileges
                Register-Result -Name $p.Name -Key $p.Key -Code $code -NotInstalledCodes @(135)
            }
        }

        # ------------------------------------------------------------ 4. MSI products
        Write-Log '--- STEP 4: MSI products (Acrobat, Reader, etc.) ---'
        foreach ($p in @($targets | Where-Object { ($_.Type -eq 'MSI' -or $_.Type -eq 'Package') -and $_.Name -notmatch $CreativeCloudPattern })) {
            if (-not (Test-Path $p.Key)) { Write-Log "$($p.Name) already removed by a prior step"; continue }
            if ($PSCmdlet.ShouldProcess($p.Name, 'Uninstall (msiexec)')) {
                $code = Invoke-Uninstaller -FilePath "$env:SystemRoot\System32\msiexec.exe" `
                    -ArgumentList "/x `"$($p.ProductCode)`" /qn /norestart REBOOT=ReallySuppress" -Label $p.Name
                # 1605 = product not installed
                Register-Result -Name $p.Name -Key $p.Key -Code $code -NotInstalledCodes @(1605)
            }
        }

        # ------------------------------------------------------------ 5. Other EXE uninstallers
        Write-Log '--- STEP 5: Other EXE uninstallers ---'
        foreach ($p in @($targets | Where-Object { $_.Type -eq 'EXE' -and $_.Name -notmatch $CreativeCloudPattern })) {
            if (-not (Test-Path $p.Key)) { Write-Log "$($p.Name) already removed by a prior step"; continue }
            $cmd = if ($p.QuietUninstall) { $p.QuietUninstall } else { $p.UninstallString }
            if (-not $cmd) { Write-Log "$($p.Name): no UninstallString" -Level ERROR; $script:failed.Add($p.Name); continue }
            $uExe, $uArgs = Split-CommandLine $cmd
            if (-not $p.QuietUninstall -and $uArgs -notmatch '(/S\b|/silent|/quiet|/qn|-silent|--silent)') {
                $uArgs = "$uArgs /S".Trim()        # NSIS/InnoSetup-style best effort; timeout protects against prompts
                Write-Log "$($p.Name): no QuietUninstallString - trying '/S' (best effort)" -Level WARN
            }
            if ($PSCmdlet.ShouldProcess($p.Name, 'Uninstall (EXE)')) {
                $code = Invoke-Uninstaller -FilePath $uExe -ArgumentList $uArgs -Label $p.Name
                Register-Result -Name $p.Name -Key $p.Key -Code $code -GraceSeconds 60
            }
        }

        # ------------------------------------------------------------ Legacy (cannot be silenced)
        foreach ($p in @($targets | Where-Object Type -eq 'Legacy')) {
            Write-Log "SKIPPED legacy PDApp-based product (no silent uninstall): $($p.Name) - remove with Creative Cloud Cleaner Tool" -Level WARN
            $script:skippedLegacy.Add($p.Name)
        }

        # ------------------------------------------------------------ 6. Creative Cloud desktop app
        # Deliberately last: "Creative Cloud Uninstaller.exe" refuses to run while any CC
        # application is still installed, so this only works once STEP 3 has emptied the device.
        # Also entered when CC ended up in $targets some other way (an explicit
        # -KeepPattern that no longer covers it) - steps 4/5 skip it, so this step owns it.
        $ccTargeted = @($targets | Where-Object { $_.Name -match $CreativeCloudPattern }).Count -gt 0
        if ($RemoveCreativeCloud -or $ccTargeted) {
            Write-Log '--- STEP 6: Adobe Creative Cloud desktop app ---'
            $ccEntries = @(Get-AdobeProduct | Where-Object { $_.Name -match $CreativeCloudPattern })
            $ccBlockers = @(Get-AdobeProduct | Where-Object { $_.Type -eq 'HD' -and $_.Name -notmatch $CreativeCloudPattern })

            if ($ccBlockers.Count -gt 0 -and $WhatIfPreference) {
                # Nothing was actually uninstalled in a dry run, so every app still looks like a blocker.
                Write-Log "What if: would uninstall the Creative Cloud desktop app here, once STEP 3 has removed $($ccBlockers.Count) CC app(s)."
            }
            elseif ($ccBlockers.Count -gt 0) {
                Write-Log "Not removing Creative Cloud: $($ccBlockers.Count) CC app(s) still installed - $($ccBlockers.Name -join '; '). Adobe's uninstaller would decline. Fix those first, then re-run." -Level ERROR
                foreach ($cc in $ccEntries) { $script:failed.Add("$($cc.Name) (blocked by remaining CC apps)") }
            }
            elseif ($ccEntries.Count -eq 0) {
                Write-Log 'Creative Cloud desktop app is not installed.'
                $script:ccRemoved = $true
                $script:protectCcPaths = $false
            }
            else {
                # Nothing is left that needs the CC runtime, so stop all of it now.
                foreach ($svcName in @('AdobeUpdateService', 'AGSService', 'AGMService', 'AdobeARMservice')) {
                    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                    if ($svc -and $svc.Status -eq 'Running' -and $PSCmdlet.ShouldProcess($svcName, 'Stop service')) {
                        try { Stop-Service -Name $svcName -Force -ErrorAction Stop; Write-Log "Stopped service: $svcName" }
                        catch { Write-Log "Could not stop ${svcName}: $_" -Level WARN }
                    }
                }
                $ccProcs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
                    $_.ProcessName -match 'Adobe|Creative ?Cloud|CCXProcess|CCLibrary|CoreSync|AdobeIPCBroker|AdobeNotificationClient|node'
                } | Where-Object {
                    # 'node' only when it is Adobe's own copy - never a developer's Node.js
                    $_.ProcessName -ne 'node' -or ($_.Path -and $_.Path -match '\\Adobe\\')
                })
                foreach ($proc in $ccProcs) {
                    if ($PSCmdlet.ShouldProcess("$($proc.ProcessName) (PID $($proc.Id))", 'Stop Creative Cloud process')) {
                        try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop; Write-Log "Stopped: $($proc.ProcessName) (PID $($proc.Id))" }
                        catch {
                            if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) { Write-Log "Could not stop $($proc.ProcessName): $_" -Level WARN }
                            else { Write-Log "  $($proc.ProcessName) (PID $($proc.Id)) already exited" }
                        }
                    }
                }
                Start-Sleep -Seconds 3

                # -u is the silent switch. Fall back to the registry UninstallString, which
                # points at the same binary, if the well-known paths have moved.
                $ccUninstaller = @(
                    "${env:ProgramFiles(x86)}\Adobe\Adobe Creative Cloud\Utils\Creative Cloud Uninstaller.exe",
                    "$env:ProgramFiles\Adobe\Adobe Creative Cloud\Utils\Creative Cloud Uninstaller.exe",
                    "${env:ProgramFiles(x86)}\Common Files\Adobe\Adobe Desktop Common\HDBox\Creative Cloud Uninstaller.exe"
                ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

                $ccArgs = '-u'
                if (-not $ccUninstaller) {
                    $ccMain = $ccEntries | Where-Object { $_.UninstallString } | Select-Object -First 1
                    if ($ccMain) {
                        $ccUninstaller, $ccArgs = Split-CommandLine $ccMain.UninstallString
                        if (-not $ccArgs) { $ccArgs = '-u' }
                        Write-Log "Creative Cloud Uninstaller.exe not at a known path - using registry UninstallString: $ccUninstaller $ccArgs" -Level WARN
                    }
                }

                if (-not $ccUninstaller) {
                    Write-Log 'Creative Cloud Uninstaller.exe not found and no usable UninstallString.' -Level ERROR
                    foreach ($cc in $ccEntries) { $script:failed.Add("$($cc.Name) (no uninstaller)") }
                }
                elseif ($PSCmdlet.ShouldProcess('Adobe Creative Cloud desktop app', 'Uninstall (Creative Cloud Uninstaller.exe)')) {
                    $code = Invoke-Uninstaller -FilePath $ccUninstaller -ArgumentList $ccArgs -Label 'Adobe Creative Cloud'
                    foreach ($cc in $ccEntries) {
                        Register-Result -Name $cc.Name -Key $cc.Key -Code $code -GraceSeconds 180 -WaitProcess 'Creative Cloud Uninstaller'
                    }
                    $script:ccRemoved = -not (@(Get-AdobeProduct | Where-Object { $_.Name -match $CreativeCloudPattern }).Count)
                    if ($script:ccRemoved) {
                        # Safe now to treat the CC runtime folders as leftovers.
                        $script:protectCcPaths = $false
                        Write-Log 'Creative Cloud runtime paths released for cleanup.'
                    }
                }
            }
        }

        # ------------------------------------------------------------ 7. Leftovers
        Write-Log '--- STEP 7: Leftovers ---'
        foreach ($t in (Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match 'Adobe Acrobat Update' })) {
            if ($PSCmdlet.ShouldProcess($t.TaskName, 'Unregister scheduled task')) {
                try { Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false -ErrorAction Stop; Write-Log "Removed task: $($t.TaskName)" }
                catch { Write-Log "Could not remove task $($t.TaskName): $_" -Level WARN }
            }
        }
        if ($RemoveLeftoverFolders) {
            $remainingLocs = @(Get-AdobeProduct | Where-Object InstallLocation | ForEach-Object { $_.InstallLocation.TrimEnd('\') })
            foreach ($root in $adobeRoots) {
                foreach ($dir in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
                    $owned = $remainingLocs | Where-Object { $dir.FullName.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }
                    if ((Test-ProtectedPath -Path $dir.FullName) -or $owned) { continue }
                    if ($PSCmdlet.ShouldProcess($dir.FullName, 'Remove leftover folder')) {
                        try { Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop; Write-Log "Removed folder: $($dir.FullName)" }
                        catch { Write-Log "Could not remove $($dir.FullName): $_" -Level WARN }
                    }
                }
            }
        }
    }

    # ---------------------------------------------------------------- 8. ProgramData\Adobe
    # Outside the targets block on purpose: worth running even when there was nothing left
    # to uninstall (this folder survives every Adobe uninstaller).
    if ($CleanProgramData) {
        Write-Log '--- STEP 8: Clearing ProgramData\Adobe ---'
        $adobeProgramData = Join-Path $env:ProgramData 'Adobe'

        if (-not (Test-Path -LiteralPath $adobeProgramData)) {
            Write-Log "Not present: $adobeProgramData"
        }
        else {
            # Decided from what is actually installed, not from the switches: if a Creative
            # Cloud desktop app survived (kept by design, or its removal failed), wiping
            # SLStore/caps deactivates it and forces a re-sign-in.
            $ccStillInstalled = @(Get-AdobeProduct | Where-Object { $_.Name -match $CreativeCloudPattern }).Count -gt 0
            $keepChild = if ($ccStillInstalled) { $ProgramDataLicensingChild } else { @() }
            if ($keepChild.Count) {
                Write-Log "Creative Cloud still installed - preserving licensing state: $($keepChild -join ', ')" -Level WARN
            }

            $pdItems = @(Get-ChildItem -LiteralPath $adobeProgramData -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notin $keepChild })

            if ($pdItems.Count -eq 0) {
                Write-Log "Nothing to remove under $adobeProgramData"
            }
            foreach ($item in $pdItems) {
                if (-not $PSCmdlet.ShouldProcess($item.FullName, 'Take ownership and delete')) { continue }
                # SLStore and friends are SYSTEM-owned with ACLs that deny delete even to
                # Administrators, so ownership has to be taken before Remove-Item succeeds.
                # Both tools write to stderr on files they cannot touch; with
                # $ErrorActionPreference = 'Stop' that becomes a terminating NativeCommandError,
                # so it is relaxed for the two calls and their output is discarded.
                $prevEap = $ErrorActionPreference
                $ErrorActionPreference = 'Continue'
                try {
                    if ($item.PSIsContainer) {
                        & takeown.exe /F $item.FullName /A /R /D Y  *>&1 | Out-Null
                        & icacls.exe  $item.FullName /grant '*S-1-5-32-544:(OI)(CI)F' /T /C /Q  *>&1 | Out-Null
                    }
                    else {
                        & takeown.exe /F $item.FullName /A  *>&1 | Out-Null
                        & icacls.exe  $item.FullName /grant '*S-1-5-32-544:F' /C /Q  *>&1 | Out-Null
                    }
                }
                catch { Write-Log "takeown/icacls failed on $($item.FullName): $_" -Level WARN }
                finally { $ErrorActionPreference = $prevEap }

                try {
                    Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed: $($item.FullName)"
                }
                catch { Write-Log "Could not remove $($item.FullName): $_" -Level WARN }
            }

            if (-not $WhatIfPreference) {
                $pdLeft = @(Get-ChildItem -LiteralPath $adobeProgramData -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notin $keepChild })
                if ($pdLeft.Count -eq 0) { Write-Log "Cleared: $adobeProgramData" -Level SUCCESS }
                else { Write-Log "$($pdLeft.Count) item(s) could not be removed from ${adobeProgramData}: $($pdLeft.Name -join '; ')" -Level WARN }
            }
        }
    }

    # ---------------------------------------------------------------- Summary + sentinel
    $finalInventory = @(Get-AdobeProduct)
    $remaining = @($finalInventory | Where-Object { -not $_.Keep -and ($_.Type -ne 'Package' -or $RemovePackageWrappers) })
    $kept = @($finalInventory | Where-Object Keep)
    $remainingLabel = if ($WhatIfPreference) { 'Would remove   ' } else { 'Still installed' }

    Write-Log '=============================================='
    Write-Log 'RESULTS SUMMARY'
    Write-Log "Removed         : $($script:removed.Count)  $(if ($script:removed.Count) { '- ' + ($script:removed -join '; ') })"
    Write-Log "Failed          : $($script:failed.Count)  $(if ($script:failed.Count) { '- ' + ($script:failed -join '; ') })" -Level $(if ($script:failed.Count) { 'ERROR' } else { 'INFO' })
    Write-Log "Skipped legacy  : $($script:skippedLegacy.Count)  $(if ($script:skippedLegacy.Count) { '- ' + ($script:skippedLegacy -join '; ') })"
    Write-Log "$remainingLabel : $($remaining.Count)  $(if ($remaining.Count) { '- ' + ($remaining.Name -join '; ') })" -Level $(if ($remaining.Count -and -not $WhatIfPreference) { 'WARN' } else { 'INFO' })
    if ($wrappers.Count -gt 0 -and -not $RemovePackageWrappers) {
        Write-Log "Package wrappers: $($wrappers.Count) left registered (ignored by detection) - $($wrappers.Name -join '; ')"
    }
    Write-Log "Kept (by design): $($kept.Count)  $(if ($kept.Count) { '- ' + ($kept.Name -join '; ') })"
    if ($RemoveCreativeCloud -or $CleanProgramData) {
        $ccState = if (@($finalInventory | Where-Object { $_.Name -match $CreativeCloudPattern }).Count) { 'STILL INSTALLED' } else { 'removed / absent' }
        Write-Log "Creative Cloud  : $ccState   ProgramData cleaned: $CleanProgramData"
    }
    Write-Log "Reboot required : $($script:rebootRequired)"
    Write-Log "Elapsed         : $([math]::Round(((Get-Date) - $script:startTime).TotalMinutes, 1)) min"
    Write-Log '=============================================='

    $completed = if ($remaining.Count -eq 0 -and -not $WhatIfPreference) { 1 } else { 0 }
    if ($PSCmdlet.ShouldProcess($SentinelKey, 'Write detection sentinel')) {
        try {
            if (-not (Test-Path $SentinelKey)) { New-Item -Path $SentinelKey -Force | Out-Null }
            Set-ItemProperty -Path $SentinelKey -Name 'Completed'     -Value $completed -Type DWord -Force
            Set-ItemProperty -Path $SentinelKey -Name 'Remaining'     -Value $remaining.Count -Type DWord -Force
            Set-ItemProperty -Path $SentinelKey -Name 'ScriptVersion' -Value $ScriptVersion -Type String -Force
            Set-ItemProperty -Path $SentinelKey -Name 'LastRun'       -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Type String -Force
            Set-ItemProperty -Path $SentinelKey -Name 'LastLog'       -Value $LogFile -Type String -Force
            Set-ItemProperty -Path $SentinelKey -Name 'FullRemoval'   -Value ([int][bool]$RemoveCreativeCloud) -Type DWord -Force
            Write-Log "Sentinel written: $SentinelKey Completed=$completed" -Level SUCCESS
        }
        catch { Write-Log "Failed to write sentinel: $_" -Level ERROR }
    }

    if ($remaining.Count -gt 0 -and -not $WhatIfPreference) { Write-Log 'Script complete with products remaining.' -Level ERROR; exit 1 }
    if ($script:rebootRequired) { Write-Log 'Script complete - reboot required.' -Level WARN; exit 3010 }
    Write-Log 'Script complete.' -Level SUCCESS
    exit 0
}
