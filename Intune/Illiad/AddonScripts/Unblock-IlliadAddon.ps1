 <# 
.SYNOPSIS
  Unblock all files for an ILLiad add-on (or any folder) by removing Zone.Identifier.

.DESCRIPTION
  - Uses Unblock-File first (preferred), falls back to removing the ADS if needed.
  - Recurses through subfolders by default.
  - Writes a log to C:\ProgramData\ILLiadAddonUnblock\unblock.log
  - Exits 0 on success, 1 if path not found or unhandled errors occurred.

.PARAMETER AddonPath
  Root folder of the add-on files. Default is the Alma NCIP Integration path.

.PARAMETER NoRecurse
  If supplied, only processes the top-level folder.

.PARAMETER WhatIf
  Preview actions without making changes.

.EXAMPLE
  .\Unblock-IlliadAddon.ps1
  .\Unblock-IlliadAddon.ps1 -AddonPath "C:\Program Files (x86)\ILLiad\Addons\MyAddon"

#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [string]$AddonPath = "C:\Program Files (x86)\ILLiad\Addons\AlmaNcipIntegration",
  [switch]$NoRecurse
)

# ---- Setup logging ----
$LogDir  = "C:\ProgramData\ILLiadAddonUnblock"
$LogFile = Join-Path $LogDir "unblock.log"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
function Write-Log { param([string]$Msg) $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); "$stamp`t$Msg" | Tee-Object -FilePath $LogFile -Append }

Write-Log "========== Start run =========="
Write-Log "AddonPath: $AddonPath"

# ---- Validate path ----
if (-not (Test-Path -LiteralPath $AddonPath)) {
  Write-Log "ERROR: Path not found: $AddonPath"
  Write-Error "Path not found: $AddonPath"
  exit 1
}

# ---- Gather files ----
$searchOpt = if ($NoRecurse) { @{} } else { @{ Recurse = $true } }
$files = Get-ChildItem -LiteralPath $AddonPath -File @searchOpt -Force -ErrorAction SilentlyContinue

if (-not $files) {
  Write-Log "No files found under: $AddonPath"
  exit 0
}

# Helper to test if a file is "blocked" (has Zone.Identifier)
function Test-Blocked {
  param([System.IO.FileInfo]$File)
  try {
    # PS 5+ supports -Stream
    $stream = Get-Item -LiteralPath $File.FullName -Stream "Zone.Identifier" -ErrorAction SilentlyContinue
    return [bool]$stream
  } catch { return $false }
}

# ---- Process files ----
$blocked = @()
$unblocked = 0
$failed = 0

foreach ($f in $files) {
  if (-not (Test-Blocked -File $f)) { continue }
  $blocked += $f.FullName
}

Write-Log ("Blocked files detected: {0}" -f $blocked.Count)
foreach ($b in $blocked) {
  try {
    if ($PSCmdlet.ShouldProcess($b, "Unblock")) {
      # 1) Try Unblock-File
      try {
        Unblock-File -LiteralPath $b -ErrorAction Stop
        Write-Log "Unblocked via Unblock-File: $b"
        $unblocked++
        continue
      } catch {
        # 2) Fallback: remove Zone.Identifier ADS directly
        try {
          Remove-Item -LiteralPath $b -Stream "Zone.Identifier" -Force -ErrorAction Stop
          Write-Log "Removed ADS Zone.Identifier: $b"
          $unblocked++
          continue
        } catch {
          Write-Log "ERROR: Failed to remove ADS for: $b :: $($_.Exception.Message)"
          $failed++
        }
      }
    }
  } catch {
    Write-Log "ERROR: Unhandled error on $b :: $($_.Exception.Message)"
    $failed++
  }
}

# ---- Summary ----
Write-Log "Summary: blocked found=$($blocked.Count); unblocked=$unblocked; failed=$failed"
Write-Log "=========== End run ===========" 

if ($failed -gt 0) {
  Write-Warning "Some files could not be unblocked. See log: $LogFile"
  exit 1
} else {
  Write-Output "All done. Unblocked $unblocked file(s). Log: $LogFile"
  exit 0
} 
