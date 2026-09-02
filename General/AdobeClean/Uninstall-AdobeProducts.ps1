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
           b. Anything still present is removed per-app with the HDBox
              uninstaller command stored in the registry UninstallString:
                Set-up.exe --uninstall=1 --sapCode=X --baseVersion=Y
                           --platform=win64 --deleteUserPreferences=false
              (--deleteUserPreferences is forced on the line; without it the
              uninstaller shows a dialog and hangs under SYSTEM.)
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
    Version : 1.1.1
    Run As  : SYSTEM (Intune) or local Administrator

    CHANGELOG
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
    $ScriptVersion = '1.1.1'

    # Works when run as a file (PSScriptRoot set) AND when pasted into Intune (CWD = unpacked package)
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

    $SentinelKey = 'HKLM:\SOFTWARE\LIBR\AdobeUninstall'

    # Creative Cloud runtime that lives under Program Files\Adobe and must never be
    # killed or deleted while CC is kept (CoreSync = CC file sync, CCX = CC Experience).
    $ProtectedPathPattern = @(
        'Adobe Creative Cloud',
        'Creative Cloud Experience',
        'Adobe Sync',
        'Adobe Desktop Common',
        'AdobeGCClient'
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

                $sap = $null; $base = $null
                if ($type -eq 'HD') {
                    if ($us -match '--sapCode=(\S+)') { $sap = $Matches[1] }
                    if ($us -match '--(?:baseVersion|productVersion)=(\S+)') { $base = $Matches[1] }
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
            $proc = Start-Process @psi
            if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
                Write-Log "TIMEOUT after $TimeoutMinutes min - killing $Label (PID $($proc.Id))" -Level ERROR
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                return -1
            }
            return $proc.ExitCode
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

    function Register-Result {
        param([string]$Name, [int]$Code, [int[]]$OkCodes = @(0), [int[]]$NotInstalledCodes = @())
        if ($Code -in $OkCodes) {
            Write-Log "Removed: $Name" -Level SUCCESS; $script:removed.Add($Name)
        }
        elseif ($Code -eq 3010 -or $Code -eq 1641) {
            Write-Log "Removed: $Name (reboot required)" -Level WARN
            $script:removed.Add($Name); $script:rebootRequired = $true
        }
        elseif ($Code -in $NotInstalledCodes) {
            Write-Log "$Name reported not installed (exit $Code) - treating as removed" -Level WARN
            $script:removed.Add($Name)
        }
        else {
            Write-Log "$Name uninstall returned exit code $Code" -Level ERROR
            $script:failed.Add("$Name (exit $Code)")
        }
    }
}

process {
    Write-Log '=============================================='
    Write-Log "LIBR Adobe Product Uninstall v$ScriptVersion"
    Write-Log "Computer : $env:COMPUTERNAME   User: $env:USERNAME"
    Write-Log "Keep     : $($KeepPattern -join ' | ')"
    Write-Log "Options  : RemoveUserPreferences=$RemoveUserPreferences RemovePackageWrappers=$RemovePackageWrappers RemoveLeftoverFolders=$RemoveLeftoverFolders WhatIf=$WhatIfPreference"
    Write-Log "Timeout  : $TimeoutMinutes min per uninstaller"
    Write-Log '=============================================='

    # ---------------------------------------------------------------- Pre-flight
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { Write-Log 'Must run as Administrator or SYSTEM. Exiting.' -Level ERROR; exit 1 }

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
        $hdAll = @($targets | Where-Object { $_.Type -eq 'HD' })
        foreach ($p in $hdAll) {
            if (-not (Test-Path $p.Key)) { continue }                                  # already gone
            if ($p.Name -in $script:removed) { continue }
            if (-not $p.UninstallString) { Write-Log "$($p.Name): no UninstallString" -Level ERROR; $script:failed.Add($p.Name); continue }

            $uExe, $uArgs = Split-CommandLine $p.UninstallString
            $prefValue = if ($RemoveUserPreferences) { 'true' } else { 'false' }
            if ($uArgs -match '--deleteUserPreferences=') {
                $uArgs = $uArgs -replace '--deleteUserPreferences=\S+', "--deleteUserPreferences=$prefValue"
            } else {
                $uArgs = "$uArgs --deleteUserPreferences=$prefValue".Trim()
            }
            if ($PSCmdlet.ShouldProcess($p.Name, 'Uninstall (HDBox)')) {
                $code = Invoke-Uninstaller -FilePath $uExe -ArgumentList $uArgs -Label $p.Name
                # 135 = not installed; 105 = insufficient privileges
                Register-Result -Name $p.Name -Code $code -NotInstalledCodes @(135)
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
                Register-Result -Name $p.Name -Code $code -NotInstalledCodes @(1605)
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
                Register-Result -Name $p.Name -Code $code
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
