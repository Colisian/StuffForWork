# Return 0 only when GlobalProtect 6.2.8 is installed. Otherwise return 1.
$target = [version]'6.2.8.0'  # adjust to exact file version if needed
# Prefer file version from PanGPS.exe if present:
$exe = @(
  "C:\Program Files\Palo Alto Networks\GlobalProtect\PanGPS.exe",
  "C:\Program Files (x86)\Palo Alto Networks\GlobalProtect\PanGPS.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if($exe){
  $v = [version](Get-Item $exe).VersionInfo.FileVersion
  if($v -ge $target){ exit 0 } else { exit 1 }
} else {
  # fallback to ARP entries if file not present
  $roots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  $hit = foreach($r in $roots){
    Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object {
      $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
      if($p.DisplayName -like 'GlobalProtect*' -and $p.DisplayVersion){
        [PSCustomObject]@{Ver=[version]$p.DisplayVersion}
      }
    }
  }
  
  $hit = $hit | Sort-Object Ver -Descending | Select-Object -First 1

  if($hit -and $hit.Ver -ge $target){ exit 0 } else { exit 1 }
}

