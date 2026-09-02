<#
.SYNOPSIS
    Uninstall-AdobeProducts.ps1
    Silently removes every installed Adobe product on a Windows device EXCEPT
    the Adobe Creative Cloud desktop app (and the services it depends on).

.DESCRIPTION
    Enumerates the Uninstall registry hives (64-bit + WOW6432Node), selects
    entries published by Adobe, drops anything matching -KeepPattern, then
    removes the rest using the correct mechanism per installer type:

      1. Creative Cloud / HyperDrive apps (Photoshop, Illustrator, InDesign,
         Premiere Pro, After Effects, Lightroom, Bridge, Media Encoder,
         Substance, etc.)
           a. If AdobeUninstaller.exe (Admin Console > Packages > Tools) is
              found next to the script, it is used first in one call:
                AdobeUninstaller.exe --products=PHSP#25.0,ILST#28.0,...
           b. Anything still present is removed per-app with Adobe's silent
              HDBox setup engine, using sapCode/version parsed from the
              registry UninstallString:
                HDBox\Setup.exe --uninstall=1 --sapCode=X --baseVersion=Y
                                --platform=win64 --deleteUserPreferences=false
              (Setup.exe ~850 KB is the HD engine; the 14 MB Set-up.exe next
              to it is the CC installer bootstrapper and is not used unless
              Setup.exe is absent.)
              The registry UninstallString itself is NOT run: on current CC
              builds it points at HDBox\Uninstaller.exe --mode=2, which is
              the Programs-and-Features launcher. That hands off to the
              Creative Cloud desktop app (sign-in prompt), exits 0 after ~2 s,
              and removes nothing under SYSTEM. It is used only as a last
              resort when Set-up.exe cannot be found.
           c. A removal is credited ONLY when the product's registry key is
              gone afterwards - exit codes from Adobe launchers are not trusted.
      2. MSI products (Acrobat, Reader, Refresh Manager, AIR, etc.)
           msiexec /x {ProductCode} /qn /norestart REBOOT=ReallySuppress
         Admin Console PACKAGE WRAPPER MSIs (DisplayVersion 1.0.0000, e.g.
         "AdobeCC_SelfService", "LIBR-AcrobatDC") are NOT products - they are
         the deployment package registrations. Uninstalling one removes every
         product in that package, and a self-service package's only product
         is the Creative Cloud desktop app itself. They are therefore skipped
         (and ignored by detection) unless -RemovePackageWrappers is given.
      3. Other EXE uninstallers - QuietUninstallString if present, otherwise
         UninstallString with /S appended (NSIS-style), always under a timeout.
      4. Legacy CS5/CS6/early-CC apps (PDApp.exe based) cannot be silenced;
         they are logged as WARN and left for the Creative Cloud Cleaner Tool.

    Every uninstaller runs under a hard timeout so a stray dialog can never
    hang an Intune install. Progress is logged to C:\ProgramData\LIBR\Logs and
    a registry sentinel is written for Intune detection.

    Works both as a file (-File .\Uninstall-AdobeProducts.ps1) and pasted into
    the Intune Win32 "PowerShell script installer" box.

.PARAMETER LogPath
    Log directory. Default: C:\ProgramData\LIBR\Logs

.PARAMETER KeepPattern
    Regex patterns matched (case-insensitive) against DisplayName. Matching
    products are never touched. Default keeps the Creative Cloud desktop app
    and Adobe Genuine Service (CC re-installs AGS if it is removed).

.PARAMETER RemoveUserPreferences
    Pass --deleteUserPreferences=true to the Creative Cloud app uninstaller so
    per-user app settings are wiped too. Default: preferences are retained.

.PARAMETER RemovePackageWrappers
    Also run msiexec /x on Admin Console package wrapper MSIs (DisplayVersion
    1.0.0000). WARNING: a self-service package wrapper will remove the Creative
    Cloud desktop app. Off by default.

.PARAMETER RemoveLeftoverFolders
    After uninstalling, delete orphaned product folders under
    "Program Files\Adobe" and "Program Files (x86)\Adobe" that no remaining
    product owns and that do not match -KeepPattern. Never touches
    Common Files\Adobe (shared Creative Cloud runtime).

.PARAMETER AdobeUninstallerPath
    Explicit path to AdobeUninstaller.exe. Default: <script folder>\AdobeUninstaller.exe
    if present; otherwise the per-app HDBox method is used.

.PARAMETER TimeoutMinutes
    Maximum minutes to wait for any single uninstaller before it is killed.
    Default: 30

.EXAMPLE
    .\Uninstall-AdobeProducts.ps1 -WhatIf
    Lists what would be removed / kept without changing anything.

.EXAMPLE
    .\Uninstall-AdobeProducts.ps1 -KeepPattern 'Adobe Creative Cloud','Adobe Genuine Service','Adobe Acrobat'
    Removes everything Adobe except Creative Cloud, AGS and Acrobat.

.NOTES
    Author  : Oji (cmcleod1)
    Date    : 2026-09-01
    Version : 1.4.0
    Run As  : SYSTEM (Intune) or local Administrator

    CHANGELOG
      1.4.0 - VALIDATED END TO END on LIBRWKSPC010189 (2026-09-01): all 15
              CC apps removed, CC desktop app + Adobe Genuine Service kept,
              sentinel Completed=1.
            - Added $KnownBaseVersion table seeded with LRCC=1.0 (Lightroom
              ships 9.x on a base of 1.0; the blind sweep needed 22 attempts).
              Bridge needed no entry - its base is major.0.0 (16.0.0), which
              is already the second candidate.
      1.3.4 - Sweep now distinguishes 135 (wrong baseVersion) from any other
              non-zero code (baseVersion recognised, uninstall itself failed)
              and reports the recognised values plus where Adobe logs them.
      1.3.3 - baseVersion sweep now walks MAJOR versions down as well as
              minors. Bridge/Lightroom sit on a rolling train and keep an old
              base version (Adobe documents Bridge as 12.0.0) while shipping
              16.x/9.x, so the correct value was unreachable. Capped at 48
              candidates (~48 s worst case).
            - Program Files\Adobe\Common protected from -RemoveLeftoverFolders.
      1.3.2 - application.json lookup no longer depends on InstallLocation
              (empty for most HD apps): also searches Program Files\Adobe
              folders matching the product name and per-sapCode HD staging
              paths, and only trusts a file that names the sapCode.
      1.3.1 - baseVersion now read from the app's own application.json when
              present (authoritative); candidate list extended with 3-part
              forms (16.0.0) and a descending-minor sweep. Bridge/Lightroom
              failed at 135 because only 2-part forms were tried.
            - Products removed as a side effect of another app's uninstall
              (shared components like UXP WebView Support) are now counted
              and logged instead of silently skipped.
      1.3.0 - FIX: --baseVersion must be the ORIGINAL install version (27.0),
              not the current updated version the registry reports (27.10).
              Only never-updated apps worked. Now tries major.0 -> exact ->
              major.minor until the Uninstall key disappears.
            - FIX: exit codes were always $null (Start-Process handle quirk),
              coerced to 0 in logs. Handle is now cached; real codes logged.
      1.2.2 - HD engine probe now prefers HDBox\Setup.exe (the engine) over
              Set-up.exe (the CC installer bootstrapper) - both exist on
              current builds and the wrong one was being picked first.
      1.2.1 - Abort when run from a 32-bit host on 64-bit Windows (registry
              redirection hides 64-bit products); log host bitness in header.
      1.2.0 - FIX: per-app CC uninstall ran the registry UninstallString
              (HDBox\Uninstaller.exe --mode=2), which is a GUI launcher that
              delegates to the CC desktop app (sign-in popup) and exits 0
              without removing anything. Now builds the documented silent
              command against HDBox\Set-up.exe / Setup.exe from sapCode +
              version parsed out of the registry string.
            - FIX: success is verified by the product's Uninstall key
              disappearing, not by exit code. Per-uninstall duration logged.
      1.1.1 - Inventory tag now shows SKIP (not REMOVE) for untargeted package
              wrappers; type column widened for 'Package'.
            - Options line records -RemovePackageWrappers and the timeout;
              summary reports elapsed minutes (watch Intune's install timeout).
      1.1.0 - Logging no longer suppressed by -WhatIf (Add-Content -WhatIf:$false).
            - Creative Cloud runtime processes/folders (CoreSync under
              "Adobe Sync", "Adobe Creative Cloud Experience", HDBox) are
              protected by $ProtectedPathPattern regardless of -KeepPattern.
            - Admin Console package wrapper MSIs classified as 'Package' and
              skipped by default (-RemovePackageWrappers to include).
            - WhatIf summary wording ("Would remove" instead of "Still installed").
      1.0.0 - Initial release.
    PS      : 5.1+ (7.x compatible)

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
    [string]$AdobeUninstallerPath,
    [int]$TimeoutMinutes = 30
)

begin {
    $ErrorActionPreference = 'Stop'
    $ScriptVersion = '1.4.0'

    # Works when run as a file (PSScriptRoot set) AND when pasted into Intune (CWD = unpacked package)
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

    $SentinelKey = 'HKLM:\SOFTWARE\LIBR\AdobeUninstall'

    # Base versions confirmed on real devices, tried before any guessing. Apps on a rolling
    # release train keep their original base version for years, so it is not derivable from
    # the installed version and the blind sweep is slow (Lightroom needed 22 attempts).
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
        <# Authoritative local source: every HD app ships an application.json carrying its
           real BaseVersion (Adobe's own docs point admins at Build\HD\<sap>\Application.json).
           Search is bounded to 3 levels under the install folder to stay fast. #>
        param([string]$InstallLocation, [string]$SapCode, [string]$ProductName)

        # Candidate roots: the registered InstallLocation (often EMPTY for HD apps), then
        # Program Files\Adobe folders whose name matches the product, then the HD product
        # staging area which keeps a per-sapCode application.json.
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

        # Walk MAJORS down. Apps on a rolling release train (Bridge, Lightroom) keep the
        # base version of their original release for years while shipping much later
        # product versions - Adobe documents Bridge as base 12.0.0. Without this the
        # correct base is unreachable. Each miss costs ~1 s and exit 135.
        if ($majOk) {
            for ($M = $majVal - 1; $M -ge 1; $M--) { $c.Add("$M.0"); $c.Add("$M.0.0") }
        }
        return @($c | Where-Object { $_ } | Select-Object -Unique | Select-Object -First $MaxCandidates)
    }

    function Register-Result {
        <# Credits a removal ONLY if the product's Uninstall registry key is gone.
           Adobe launchers (HDBox\Uninstaller.exe --mode=2) exit 0 without doing anything. #>
        param([string]$Name, [string]$Key, [int]$Code, [int[]]$NotInstalledCodes = @())
        $stillRegistered = if ($Key) { Test-Path $Key } else { $false }

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
    Write-Log "Keep     : $($KeepPattern -join ' | ')"
    Write-Log "Options  : RemoveUserPreferences=$RemoveUserPreferences RemovePackageWrappers=$RemovePackageWrappers RemoveLeftoverFolders=$RemoveLeftoverFolders WhatIf=$WhatIfPreference"
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
        # so it is left running by design (the HD uninstaller does not need it stopped).
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
                catch { Write-Log "Could not stop $($proc.ProcessName): $_" -Level WARN }
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
        # Adobe's silent HD engine. The registry UninstallString is deliberately NOT used
        # (it is the GUI launcher - see header).
        # HDBox ships BOTH Setup.exe (~850 KB, the HyperDrive engine Adobe documents for
        # --uninstall; macOS equivalent is HDBox/Setup) and Set-up.exe (~14 MB, the Creative
        # Cloud installer bootstrapper). Setup.exe is the one we want; Set-up.exe is only a
        # last-resort probe for builds that lack Setup.exe.
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
        foreach ($p in @($targets | Where-Object { $_.Type -eq 'MSI' -or $_.Type -eq 'Package' })) {
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
        foreach ($p in @($targets | Where-Object Type -eq 'EXE')) {
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
                Register-Result -Name $p.Name -Key $p.Key -Code $code
            }
        }

        # ------------------------------------------------------------ 6. Legacy (cannot be silenced)
        foreach ($p in @($targets | Where-Object Type -eq 'Legacy')) {
            Write-Log "SKIPPED legacy PDApp-based product (no silent uninstall): $($p.Name) - remove with Creative Cloud Cleaner Tool" -Level WARN
            $script:skippedLegacy.Add($p.Name)
        }

        # ------------------------------------------------------------ 7. Leftovers
        Write-Log '--- STEP 6: Leftovers ---'
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
            Write-Log "Sentinel written: $SentinelKey Completed=$completed" -Level SUCCESS
        }
        catch { Write-Log "Failed to write sentinel: $_" -Level ERROR }
    }

    if ($remaining.Count -gt 0 -and -not $WhatIfPreference) { Write-Log 'Script complete with products remaining.' -Level ERROR; exit 1 }
    if ($script:rebootRequired) { Write-Log 'Script complete - reboot required.' -Level WARN; exit 3010 }
    Write-Log 'Script complete.' -Level SUCCESS
    exit 0
}
