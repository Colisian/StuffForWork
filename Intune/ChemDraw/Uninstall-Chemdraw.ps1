 <#
uninstall-chemdraw-suite.ps1
- Run as SYSTEM (Intune) or elevated admin.
- Finds and uninstalls any installed items with DisplayName matching "ChemDraw" or "ChemDraw Suite"
  and DisplayVersion matching "23.1*". Adjust the pattern if you need a different scope.
- Logging: writes a log in %TEMP% starting with Chemdraw_Uninstall_.
- Exit codes:
    0 = success (all targeted uninstalls succeeded or none found)
    3010 = success but reboot required for at least one item
    1 = any uninstall failed
#>

$Log = Join-Path $env:TEMP ("Chemdraw_Uninstall_" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
"Started: $(Get-Date -Format u)" | Out-File $Log -Encoding UTF8

function LogWrite([string]$s) {
    $t = "$(Get-Date -Format u) $s"
    $t | Out-File $Log -Append -Encoding UTF8
}

function Run-Command {
    param(
        [string]$Exe,
        [Parameter(Mandatory=$false)]
        $Arguments
    )

    if ($null -eq $Arguments) { $argList = @() }
    elseif ($Arguments -is [array]) { $argList = $Arguments }
    else { $argList = @($Arguments) }

    LogWrite ("Running: " + $Exe + " " + ($argList -join ' '))
    try {
        $p = Start-Process -FilePath $Exe -ArgumentList $argList -Wait -PassThru -WindowStyle Hidden
        $exit = 0
        if ($p -and $p.ExitCode -ne $null) { $exit = [int]$p.ExitCode }
    } catch {
        $msg = $_.Exception.Message
        LogWrite ("Error starting " + $Exe + ": " + $msg)
        Write-Warning ("Error starting " + $Exe + ": " + $msg)
        $exit = 1
    }
    LogWrite ("ExitCode: " + $exit)
    return $exit
}

# -- discovery: look in both 64-bit & WOW6432Node uninstall registry hives
$hives = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$targets = @()
foreach ($h in $hives) {
    Get-ChildItem -Path $h -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty -Path $_.PsPath -ErrorAction SilentlyContinue
        if ($p -and $p.DisplayName) {
            # match DisplayName containing ChemDraw or ChemDraw Suite AND DisplayVersion starting with 23.1
            if (($p.DisplayName -match "ChemDraw" -or $p.DisplayName -match "ChemDraw Suite") -and $p.DisplayVersion -like "23.1*") {
                $targets += [pscustomobject]@{
                    RegistryKey = $_.PSChildName
                    Hive = $h
                    DisplayName = $p.DisplayName
                    DisplayVersion = $p.DisplayVersion
                    UninstallString = ($p.UninstallString -as [string])
                    InstallLocation = ($p.InstallLocation -as [string])
                }
            }
        }
    }
}

if (-not $targets -or $targets.Count -eq 0) {
    LogWrite "No ChemDraw 23.1.x items found. Nothing to uninstall."
    Exit 0
}

LogWrite ("Found {0} matching entries." -f $targets.Count)
$targets | ForEach-Object { LogWrite (" - " + $_.DisplayName + "  Version:" + $_.DisplayVersion + "  UninstallString: " + ($_.UninstallString -replace "`r`n"," ")) }

$globalExit = 0
$needReboot = $false

foreach ($entry in $targets) {
    LogWrite ("Processing: " + $entry.DisplayName + " (" + $entry.DisplayVersion + ")")
    $u = $entry.UninstallString
    if (-not $u) {
        LogWrite ("  No uninstall string found for " + $entry.DisplayName + " — skipping")
        $globalExit = 1
        continue
    }

    # Normalize whitespace, remove surrounding quotes for parsing
    $uClean = $u.Trim()
    # If it's an msiexec string (/I or /X or contains GUID), prefer msiexec /x {guid} /qn
    $rc = $null
    if ($uClean -match "msiexec" -or $uClean -match "MsiExec.exe") {
        $guid = $null
        if ($uClean -match "/I\s*\{?([0-9A-Fa-f\-]{36})\}?" -or $uClean -match "/X\s*\{?([0-9A-Fa-f\-]{36})\}?") {
            $guid = $matches[1]
        } elseif ($uClean -match "\{([0-9A-Fa-f\-]{36})\}") {
            $guid = $matches[1]
        }

        if ($guid) {
            LogWrite ("  Uninstall via msiexec /x {" + $guid + "} /qn REBOOT=ReallySuppress")
            $rc = Run-Command "msiexec.exe" @("/x","{$guid}","/qn","REBOOT=ReallySuppress")
        } else {
            # Run the uninstall string; if it lacks a quiet switch, try adding /qn or /S as appropriate
            LogWrite ("  msiexec string found but no GUID extracted; running uninstall string fallback")
            $uNoQuotes = $uClean.Trim('"')
            # split exe and args
            if ($uNoQuotes -match '^\s*"([^"]+)"\s*(.*)$') { $exePath = $matches[1]; $uArgs = $matches[2] } else {
                $parts = $uNoQuotes -split '\s+',2
                $exePath = $parts[0]; $uArgs = if ($parts.Length -gt 1) { $parts[1] } else { "" }
            }
            if ($uArgs -match "/qn|/quiet|/S|/silent") {
                $rc = Run-Command $exePath $uArgs
            } else {
                # try to append /S then /quiet
                $rc = Run-Command $exePath "/S"
                if ($rc -ne 0) { $rc = Run-Command $exePath "/quiet" }
            }
        }
    } else {
        # Non-msiexec (EXE). Try to parse and run with silent switches
        if ($uClean -match '^\s*"([^"]+)"\s*(.*)$') { $exe = $matches[1]; $uArgs = $matches[2] } else {
            $parts = $uClean -split '\s+',2; $exe = $parts[0]; $uArgs = if ($parts.Length -gt 1) { $parts[1] } else { "" }
        }

        if ($uArgs -match '/S|/quiet|/silent|/uninstall|/qn') {
            $rc = Run-Command $exe $uArgs
        } else {
            # try common silent switches
            $rc = Run-Command $exe "/S"
            if ($rc -ne 0) { $rc = Run-Command $exe "/quiet" }
        }
    }

    if ($rc -eq $null) { $rc = 1 }  # defensive
    if ($rc -eq 3010) { $needReboot = $true; LogWrite ("  Uninstall returned 3010 (reboot required)") }
    elseif ($rc -ne 0) { LogWrite ("  Uninstall returned non-zero: " + $rc); $globalExit = 1 }
    else { LogWrite ("  Uninstall returned 0 (success)") }
}

if ($needReboot) {
    LogWrite "One or more uninstalls requested a reboot. Exiting 3010."
    Exit 3010
}

LogWrite ("Finished. GlobalExit = " + $globalExit)
Exit $globalExit 
