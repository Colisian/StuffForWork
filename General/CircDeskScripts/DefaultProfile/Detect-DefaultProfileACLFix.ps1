<#
.SYNOPSIS
    Intune Win32 app CUSTOM DETECTION script: Default profile ACL fix.

.DESCRIPTION
    Read-only. Makes no changes.

    Reports "installed" (exit 0 + text on STDOUT) only when BOTH are true:
      - No explicit "Allow" entry anywhere in C:\Users\Default gives write-type
        rights to Users / Everyone / Authenticated Users / INTERACTIVE
      - Default\Desktop contains no files except desktop.ini

    Otherwise it exits 1 with no STDOUT, so Intune treats the app as
    "not installed" and runs the install script. Because this checks the real
    permissions and not a marker, the fix gets re-applied if the problem comes back.

    Intune setting: "Run script as 32-bit process on 64-bit clients" = No

.NOTES
    Version : 1.0
#>

$ProfileRoot = 'C:\Users\Default'
$Desktop     = Join-Path $ProfileRoot 'Desktop'

$BroadSids = @('S-1-5-32-545', 'S-1-1-0', 'S-1-5-11', 'S-1-5-4')
$WriteMask = [long](0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor
                    0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000)

if (-not (Test-Path -LiteralPath $ProfileRoot)) { exit 1 }

# 1. Any files on the Default desktop?
$stray = @(Get-ChildItem -LiteralPath $Desktop -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'desktop.ini' })
if ($stray.Count -gt 0) { exit 1 }

# 2. Any write access for broad groups? (junctions skipped)
$rp    = [System.IO.FileAttributes]::ReparsePoint
$items = @(Get-Item -LiteralPath $ProfileRoot -Force) +
         @(Get-ChildItem -LiteralPath $ProfileRoot -Recurse -Force -ErrorAction SilentlyContinue |
             Where-Object { -not ($_.Attributes -band $rp) })

foreach ($item in $items) {
    try {
        $sec = $item.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        foreach ($r in $sec.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier])) {
            if ($r.AccessControlType -eq 'Allow' -and
                $BroadSids -contains $r.IdentityReference.Value -and
                (([long][int]$r.FileSystemRights) -band $WriteMask)) {
                exit 1   # Problem found -> "not installed"
            }
        }
    }
    catch { continue }   # Unreadable item: skip, don't fail detection
}

Write-Output 'Default profile is locked down'
exit 0