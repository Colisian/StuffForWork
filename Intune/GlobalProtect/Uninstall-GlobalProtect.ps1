<# 
 Uninstall Palo Alto GlobalProtect (fast mode) + scrub leftovers.
 - Forces 64-bit when launched from 32-bit IME
 - Fast path: if only PanSetup key lingers, scrub + refresh IME and exit quickly
 - Uninstalls via known GUIDs first (6.2.8), then any MSI-based GP
 - Cleans files/services/shortcuts; optional deep clean for user hives, tasks, firewall
 - Scrubs PanSetup + stale ARP keys in BOTH 64-bit and 32-bit registry views
 - Restarts IME + nudges detection only when state changed

 Safe to re-run. Returns 0 when GP is gone; 1 otherwise.
#>

$ErrorActionPreference = 'Stop'

# ---- Speed toggles ----
$EnableMsiLogging = $false   # set $true only when troubleshooting
$EnableDeepClean  = $false   # set $true for stubborn cases (per-user/Tasks/Firewall)

# --- Relaunch in 64-bit if running as 32-bit (IME is 32-bit) ---
if (-not [Environment]::Is64BitProcess) {
  $sysnative = "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe"
  if (Test-Path $sysnative) {
    & $sysnative -ExecutionPolicy Bypass -File "$PSCommandPath"
    exit $LASTEXITCODE
  }
}

function Write-Log($msg) {
  $ts = (Get-Date).ToString("s")
  Write-Output "[$ts] $msg"
}

# --- Logging ---
$LogRoot = "$env:ProgramData\Intune\Logs"
New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
$MsiLog = Join-Path $LogRoot "GP-Uninstall.msi.log"
$Changed = $false

# --- IME refresh (fast) ---
function Fast-IME-Refresh {
  Write-Log "Refreshing Intune Management Extension..."
  try {
    Stop-Service IntuneManagementExtension -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Service IntuneManagementExtension
  } catch {
    Write-Log "WARN: IME restart issue: $($_.Exception.Message)"
  }
  foreach ($t in @(
      '\Microsoft\Intune\Schedule #1 created by enrollment client',
      '\Microsoft\Intune Management Extension\SideCar Policy',
      '\Microsoft\Intune Management Extension\Tasks\Detection'
  )) {
    try {
      $taskPath = ($t -replace '[^\\]+$',''); $taskName = ($t -split '\\')[-1]
      Start-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
    } catch { }
  }
}

# --- Helpers ---
function Remove-IfExists { param([string]$Path, [switch]$Recurse)
  if (Test-Path -LiteralPath $Path) {
    try { if ($Recurse) { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop } else { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop }
      Write-Log "Removed: $Path" } catch { Write-Log "WARN: $($_.Exception.Message)" }
  }
}

function Stop-GP {
  Write-Log "Stopping GlobalProtect processes/services..."
  foreach ($p in 'PanGPA','PanGPS','GlobalProtect','GlobalProtect64') {
    Get-Process -Name $p -ErrorAction SilentlyContinue | % { try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch {} }
  }
  $svc = Get-Service -Name 'PanGPS' -ErrorAction SilentlyContinue
  if ($svc) { try { if ($svc.Status -ne 'Stopped') { Stop-Service PanGPS -Force -ErrorAction SilentlyContinue } } catch {} }
}

function Remove-ServiceIfExists { param([string]$Name)
  try { if (Get-Service -Name $Name -ErrorAction SilentlyContinue) { sc.exe delete $Name | Out-Null } } catch {}
}

function Get-GPProducts {
  $roots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
  $roots | ForEach-Object {
    Get-ItemProperty -Path $_ -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -like 'GlobalProtect*' -or $_.Publisher -like '*Palo Alto*' }
  } | Sort-Object DisplayName, DisplayVersion -Unique
}

function Get-RealPresence {
  $hasExe = (Test-Path 'C:\Program Files\Palo Alto Networks\GlobalProtect\PanGPS.exe') -or
            (Test-Path 'C:\Program Files (x86)\Palo Alto Networks\GlobalProtect\PanGPS.exe')
  $hasSvc = [bool](Get-Service -Name 'PanGPS' -ErrorAction SilentlyContinue)
  $hasArp = [bool](
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
    % { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
    ? { $_.DisplayName -like 'GlobalProtect*' -or $_.Publisher -like '*Palo Alto*' }
  )
  [pscustomobject]@{ HasExe=$hasExe; HasSvc=$hasSvc; HasArp=$hasArp }
}

# Registry cross-view helpers
function Remove-RegKeyBothViews { param([string]$RelativePath) # e.g. 'SOFTWARE\Palo Alto Networks\GlobalProtect\PanSetup'
  foreach ($view in 'Registry64','Registry32') {
    try {
      $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::$view)
      if ($base.OpenSubKey($RelativePath, $true)) { $base.DeleteSubKeyTree($RelativePath, $false); Write-Log "[$view] Removed HKLM\$RelativePath" }
    } catch { }
  }
}

function Get-ArpKeysBothViews {
  $relPaths = @('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
  $results = @()
  foreach ($view in 'Registry64','Registry32') {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::$view)
    foreach ($rel in $relPaths) {
      try {
        $uninst = $base.OpenSubKey($rel, $false)
        if ($uninst) {
          foreach ($sub in $uninst.GetSubKeyNames()) {
            $s = $uninst.OpenSubKey($sub)
            $dn = $s.GetValue('DisplayName'); $pub = $s.GetValue('Publisher')
            if (($dn -and $dn -like 'GlobalProtect*') -or ($pub -and $pub -like '*Palo Alto*')) { $results += [pscustomobject]@{View=$view; Relative="$rel\$sub"} }
          }
        }
      } catch {}
    }
  }
  $results
}

function Scrub-PanSetup-IfTrulyGone {
  $p = Get-RealPresence
  if (-not $p.HasExe -and -not $p.HasSvc -and -not $p.HasArp) {
    foreach ($rel in @('SOFTWARE\Palo Alto Networks\GlobalProtect\PanSetup',
                       'SOFTWARE\Palo Alto Networks\GlobalProtect',
                       'SOFTWARE\Palo Alto Networks')) {
      Remove-RegKeyBothViews -RelativePath $rel
    }
    $script:Changed = $true
  } else { Write-Log "PanSetup scrub skipped (GP evidence still present)." }
}

function Scrub-ARP-IfTrulyGone {
  $p = Get-RealPresence
  if (-not $p.HasExe -and -not $p.HasSvc) {
    $toRemove = Get-ArpKeysBothViews
    foreach ($k in $toRemove) {
      try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::$($k.View))
        $base.DeleteSubKeyTree($k.Relative, $false)
        Write-Log "[$($k.View)] Removed stale ARP key: HKLM\$($k.Relative)"
        $script:Changed = $true
      } catch { Write-Log "WARN: ARP key remove failed in $($k.View): HKLM\$($k.Relative) - $($_.Exception.Message)" }
    }
  } else { Write-Log "ARP scrub skipped (files/service still present)." }
}

function Clean-PerUser {
  $userRoots = Get-ChildItem 'HKU:\' -ErrorAction SilentlyContinue | ? { $_.Name -match 'S-1-5-21-' }
  foreach ($u in $userRoots) {
    $sid = Split-Path $u.Name -Leaf
    foreach ($regPath in @("Registry::HKU\$sid\Software\Palo Alto Networks\GlobalProtect","Registry::HKU\$sid\Software\Palo Alto Networks")) {
      if (Test-Path $regPath) { try { Remove-Item $regPath -Recurse -Force -ErrorAction Stop; Write-Log "Removed $regPath" } catch { Write-Log "WARN: $($_.Exception.Message)" } }
    }
    try {
      $profilePath = (Get-Item "Registry::HKU\$sid\Volatile Environment" -ErrorAction SilentlyContinue).GetValue('USERPROFILE')
      if (-not $profilePath) { $profilePath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction SilentlyContinue).ProfileImagePath }
      if ($profilePath -and (Test-Path $profilePath)) {
        Remove-IfExists -Path (Join-Path $profilePath "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Palo Alto Networks\GlobalProtect") -Recurse
        Remove-IfExists -Path (Join-Path $profilePath "Desktop\GlobalProtect.lnk")
        Remove-IfExists -Path (Join-Path $profilePath "Desktop\GlobalProtect*.lnk")
      }
    } catch {}
  }
}

function Clean-ScheduledTasks {
  try {
    Get-ScheduledTask -ErrorAction SilentlyContinue | ? { $_.TaskName -like '*GlobalProtect*' -or $_.TaskPath -like '*Palo Alto*' -or $_.TaskPath -like '*GlobalProtect*' } |
      % { try { Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction Stop; Write-Log "Removed task: $($_.TaskPath)$($_.TaskName)" } catch { Write-Log "WARN: $($_.Exception.Message)" } }
  } catch {}
}

function Clean-FirewallRules {
  try { Get-NetFirewallRule -ErrorAction SilentlyContinue | ? { $_.DisplayName -like '*GlobalProtect*' } | Remove-NetFirewallRule -ErrorAction SilentlyContinue } catch {}
}

# ---- Fast path: only PanSetup lingers? scrub + exit quickly ----
$hasExe = (Test-Path 'C:\Program Files\Palo Alto Networks\GlobalProtect\PanGPS.exe') -or (Test-Path 'C:\Program Files (x86)\Palo Alto Networks\GlobalProtect\PanGPS.exe')
$hasSvc = [bool](Get-Service -Name 'PanGPS' -ErrorAction SilentlyContinue)
$hasArp = [bool](
  Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
  % { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
  ? { $_.DisplayName -like 'GlobalProtect*' -or $_.Publisher -like '*Palo Alto*' }
)
$panSetup64 = Test-Path 'HKLM:\SOFTWARE\Palo Alto Networks\GlobalProtect\PanSetup'
$panSetup32 = Test-Path 'HKLM:\SOFTWARE\WOW6432Node\Palo Alto Networks\GlobalProtect\PanSetup'

if (-not $hasExe -and -not $hasSvc -and -not $hasArp -and ($panSetup64 -or $panSetup32)) {
  Write-Log "Fast path: only PanSetup detected. Scrubbing…"
  foreach ($rel in @('SOFTWARE\Palo Alto Networks\GlobalProtect\PanSetup','SOFTWARE\Palo Alto Networks\GlobalProtect','SOFTWARE\Palo Alto Networks')) {
    Remove-RegKeyBothViews -RelativePath $rel
  }
  $Changed = $true
  Fast-IME-Refresh
  Write-Log "Fast scrub complete."
  exit 0
}

# --- Uninstall phase ---
Stop-GP

$uninstalled = $false
if ($EnableMsiLogging) {
  $logArg = "/L*v `"$MsiLog`""
} else {
  $logArg = ""
}
$KnownGuids = @(
  '{3D50D7DC-DB90-40CA-9D84-EB5697759067}' # GlobalProtect 6.2.8
)

# Try known GUIDs first (fast)
foreach ($guid in $KnownGuids) {
  if ((Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$guid") -or (Test-Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$guid")) {
    Write-Log "Uninstalling known product code $guid…"
    $p = Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart $logArg" -Wait -PassThru
    Write-Log "msiexec exit: $($p.ExitCode)"
    if ($p.ExitCode -in 0,1605,1614,3010) { $uninstalled = $true; $Changed = $true }
  }
}

# Fallback: any other MSI-based GP entries
if (-not $uninstalled) {
  $gps = Get-GPProducts
  foreach ($gp in $gps) {
    $pc = $gp.PSChildName
    if ($pc -and $pc -match '^\{[0-9A-F\-]+\}$') {
      Write-Log "Uninstalling $($gp.DisplayName) $($gp.DisplayVersion) ($pc)…"
      $p = Start-Process msiexec.exe -ArgumentList "/x $pc /qn /norestart $logArg" -Wait -PassThru
      Write-Log "msiexec exit: $($p.ExitCode)"
      if ($p.ExitCode -in 0,1605,1614,3010) { $uninstalled = $true; $Changed = $true }
    }
  }
}

# Attempt service deletion if it lingers
Stop-GP
Remove-ServiceIfExists -Name 'PanGPS'

# --- Cleanup phase (core) ---
Remove-IfExists -Path "C:\Program Files\Palo Alto Networks\GlobalProtect" -Recurse
Remove-IfExists -Path "C:\Program Files (x86)\Palo Alto Networks\GlobalProtect" -Recurse
Remove-IfExists -Path "C:\ProgramData\Palo Alto Networks\GlobalProtect" -Recurse
Remove-IfExists -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Palo Alto Networks\GlobalProtect" -Recurse
Remove-IfExists -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\GlobalProtect.lnk"
Remove-IfExists -Path "C:\Users\Public\Desktop\GlobalProtect.lnk"

# Optional deep-clean
if ($EnableDeepClean) { Clean-PerUser }
if ($EnableDeepClean) { Clean-ScheduledTasks }
if ($EnableDeepClean) { Clean-FirewallRules }

# Optional: disable lingering virtual adapter (best-effort)
try { Get-NetAdapter -Name 'PANGP*' -ErrorAction SilentlyContinue | % { try { Disable-NetAdapter -Name $_.Name -Confirm:$false -ErrorAction SilentlyContinue } catch {} } } catch {}

# --- SAFETY SCRUBS ---
Scrub-PanSetup-IfTrulyGone
Scrub-ARP-IfTrulyGone

# --- Verify + IME refresh if changed ---
$presence   = Get-RealPresence
$stillThere = Get-GPProducts

if (-not $stillThere -and -not $presence.HasExe -and -not $presence.HasSvc) {
  Write-Log "GlobalProtect absent after operations."
  if ($Changed) { Fast-IME-Refresh }
  exit 0
} else {
  Write-Log "ERROR: GlobalProtect still detected."
  exit 1
}
