<#
uninstall-chemdraw-23.1.ps1
Robust removal of ChemDraw / ChemDraw Suite 23.1.x entries.
Writes verbose MSI logs to C:\Windows\Temp.
Exit codes:
  0    = success (no matching items remain)
  3010 = success but reboot required
  1    = failure (one or more uninstalls failed)
#>

$LogFile = "C:\Windows\Temp\Chemdraw_Uninstall_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
function Log {
    param($s)
    $t = "$(Get-Date -Format u) $s"
    $t | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Output $s
}

$versionPattern = "23.1*"
Log "Starting uninstall script. Target DisplayVersion pattern: $versionPattern"

# prefer Sysnative to avoid WOW64 redirection when running under a 32-bit host
$msiexec = Join-Path $env:windir "Sysnative\msiexec.exe"
if (-not (Test-Path $msiexec)) { $msiexec = Join-Path $env:windir "System32\msiexec.exe" }
Log ("Using msiexec: {0}" -f $msiexec)

$hives = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# discover candidates
$candidates = @()
foreach ($h in $hives) {
    Get-ChildItem -Path $h -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty -Path $_.PsPath -ErrorAction SilentlyContinue
        if ($props -and $props.DisplayName -and $props.DisplayVersion) {
            if (($props.DisplayName -match "ChemDraw" -or $props.DisplayName -match "ChemDraw Suite") -and ($props.DisplayVersion -like $versionPattern)) {
                $candidates += [pscustomobject]@{
                    Hive = $h
                    Key = $_.PSChildName
                    DisplayName = $props.DisplayName
                    DisplayVersion = $props.DisplayVersion
                    UninstallString = ($props.UninstallString -as [string])
                    InstallLocation = ($props.InstallLocation -as [string])
                }
            }
        }
    }
}

if (-not $candidates -or $candidates.Count -eq 0) {
    Log "No matching ChemDraw 23.1.x entries found. Nothing to do."
    Exit 0
}

Log ("Found {0} matching registry entry(ies):" -f $candidates.Count)
$candidates | ForEach-Object { Log (" - {0} v{1}  Key={2}  UninstallString={3}" -f $_.DisplayName, $_.DisplayVersion, $_.Key, ($_.UninstallString -replace "`r`n"," ")) }

$globalExit = 0
$needReboot = $false

foreach ($c in $candidates) {
    Log ("Processing entry: {0} (Key: {1})" -f $c.DisplayName, $c.Key)

    # extract GUID from registry key or UninstallString
    $guid = $null
    if ($c.Key -match "^\{[0-9A-Fa-f\-]{36}\}$") { $guid = $c.Key.Trim() }
    if (-not $guid -and $c.UninstallString -match "\{([0-9A-Fa-f\-]{36})\}") { $guid = "{" + $matches[1] + "}" }

    if ($guid) {
        $msiLog = "C:\Windows\Temp\Chemdraw_uninstall_verbose_$($guid.Trim('{}'))_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        Log (" - Uninstall via msiexec /x {0} (verbose log: {1})" -f $guid, $msiLog)

        try {
            $msiArgs = @("/x", $guid, "/l*v", $msiLog, "/qn", "REBOOT=ReallySuppress")
            $proc = Start-Process -FilePath $msiexec -ArgumentList $msiArgs -Wait -PassThru -WindowStyle Hidden
            $rc = $proc.ExitCode
        } catch {
            $rc = 1
            $errMsg = $_.Exception.Message
            # use -f formatting to avoid PowerShell string-parsing issues
            Log (" - ERROR starting msiexec for {0}: {1}" -f $guid, $errMsg)
        }

        Log (" - ExitCode: {0}" -f $rc)
        if ($rc -eq 3010) { $needReboot = $true }
        elseif ($rc -ne 0) {
            Log (" - Uninstall returned non-zero for {0}. See {1}" -f $guid, $msiLog)
            $globalExit = 1
        } else {
            Log (" - Uninstall succeeded for {0}" -f $guid)
        }

    } else {
        Log (" - Could not extract GUID. Attempting fallback using UninstallString: {0}" -f $c.UninstallString)
        $u = ($c.UninstallString -as [string]).Trim()
        if ($u -match '^\s*"([^"]+)"\s*(.*)$') { $exe = $matches[1]; $uArgs = $matches[2] } else { $parts = $u -split '\s+',2; $exe = $parts[0]; $uArgs = if ($parts.Length -gt 1) {$parts[1]} else {""} }

        # choose arguments (best-effort)
        if ($uArgs -match '/qn|/quiet|/S|/silent') {
            $argToUse = $uArgs
        } else {
            $argToUse = "/S"
        }

        try {
            $proc2 = Start-Process -FilePath $exe -ArgumentList $argToUse -Wait -PassThru -WindowStyle Hidden
            $rc2 = $proc2.ExitCode
        } catch {
            $rc2 = 1
            $errMsg2 = $_.Exception.Message
            Log (" - ERROR running fallback {0} {1} : {2}" -f $exe, $argToUse, $errMsg2)
        }
        Log (" - Fallback exit code: {0}" -f $rc2)
        if ($rc2 -eq 3010) { $needReboot = $true }
        elseif ($rc2 -ne 0) { $globalExit = 1 }
    }
}

# small pause then re-check registry
Start-Sleep -Seconds 3
$remaining = @()
foreach ($h in $hives) {
    Get-ChildItem -Path $h -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty -Path $_.PsPath -ErrorAction SilentlyContinue
        if ($p -and $p.DisplayName -and $p.DisplayVersion) {
            if (($p.DisplayName -match "ChemDraw" -or $p.DisplayName -match "ChemDraw Suite") -and ($p.DisplayVersion -like $versionPattern)) {
                $remaining += [pscustomobject]@{ Hive=$h; Key=$_.PSChildName; DisplayName=$p.DisplayName; Version=$p.DisplayVersion }
            }
        }
    }
}

if ($remaining.Count -gt 0) {
    Log "UNINSTALL INCOMPLETE. Remaining entries:"
    $remaining | ForEach-Object { Log (" - {0} v{1}  Key={2}" -f $_.DisplayName, $_.Version, $_.Key) }
    $globalExit = 1
} else {
    Log "All matching entries removed."
}

if ($needReboot) {
    Log "One or more uninstalls requested reboot. Exiting 3010."
    Exit 3010
}

Log ("Finished. ExitCode = {0}" -f $globalExit)
Exit $globalExit