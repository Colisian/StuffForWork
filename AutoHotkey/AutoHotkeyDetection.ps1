# Check each user’s profile for AutoHotkey
$found = Get-ChildItem C:\Users -Directory |
  Where-Object {
    Test-Path "$($_.FullName)\AppData\Local\Programs\AutoHotkey\UX\AutoHotkey.exe"
  }

if ($found) { exit 0 } else { exit 1 }
