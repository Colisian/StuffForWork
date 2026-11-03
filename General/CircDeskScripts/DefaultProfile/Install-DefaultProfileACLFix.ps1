<#
.SYNOPSIS
    Removes standard-user write access from the Default user profile (C:\Users\Default).

.DESCRIPTION
    Intune Win32 app INSTALL script. Runs as SYSTEM.

    What it does:
      1. Backs up the current permissions of C:\Users\Default (icacls /save)
      2. Quarantines user-placed files:
           - anything in Default\Desktop except desktop.ini
           - any file in the Default profile owned by a domain account (AD\<user>)
      3. Removes explicit "Allow" entries that give write-type rights to
         Users / Everyone / Authenticated Users / INTERACTIVE.
         If a removed entry also granted read access, read & execute is put back
         so nothing loses the ability to read the template.
      4. Re-checks everything and fails (exit 1) if any problem remains.

    Only the bad entries are removed. Other permissions are left alone.
    Junctions (e.g. "Application Data", "My Documents") are skipped on purpose.

    Logs, backups and quarantine:
      C:\ProgramData\UMDLibraries\DefaultProfileACLFix\  (Administrators + SYSTEM only)

.NOTES
    Version : 1.3  (fix: "Specified cast is not valid" on PowerShell 5.1 when checking inherited entries)
              1.2  (handles permission lists in non-standard order; puts them back in standard order)
              1.1  (icacls errors on junctions no longer stop the script)
    Exit    : 0 = success, 1 = failure
#>

#region --- Relaunch in 64-bit PowerShell if started from a 32-bit host ---
if ($env:PROCESSOR_ARCHITEW6432 -eq 'AMD64' -and $PSCommandPath) {
    $ps64 = Join-Path $env:WINDIR 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    & $ps64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}
#endregion

$ErrorActionPreference = 'Stop'

#region --- Configuration ---
$Version         = '1.3'
$ProfileRoot     = 'C:\Users\Default'
$BaseDir         = 'C:\ProgramData\UMDLibraries\DefaultProfileACLFix'
$RegKey          = 'HKLM:\SOFTWARE\UMDLibraries\DefaultProfileACLFix'
$DomainNetBIOS   = 'AD'      # Files owned by AD\<user> inside the Default profile are quarantined
$QuarantineFiles = $true     # $true = move to quarantine folder, $false = delete

# Groups that should never have write access anywhere in the Default profile
$BroadSids = @(
    'S-1-5-32-545',  # BUILTIN\Users
    'S-1-1-0',       # Everyone
    'S-1-5-11',      # NT AUTHORITY\Authenticated Users
    'S-1-5-4'        # NT AUTHORITY\INTERACTIVE
)

# Any of these bits = the group can create, change, or delete something
$WriteMask = [long](
    0x2        -bor  # WriteData / CreateFiles
    0x4        -bor  # AppendData / CreateDirectories
    0x10       -bor  # WriteExtendedAttributes
    0x40       -bor  # DeleteSubdirectoriesAndFiles
    0x100      -bor  # WriteAttributes
    0x10000    -bor  # Delete
    0x40000    -bor  # ChangePermissions
    0x80000    -bor  # TakeOwnership
    0x10000000 -bor  # GENERIC_ALL
    0x40000000       # GENERIC_WRITE
)
#endregion

#region --- Paths ---
$Stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogDir  = Join-Path $BaseDir 'Logs'
$BkpDir  = Join-Path $BaseDir 'Backups'
$QDir    = Join-Path $BaseDir "Quarantine\$Stamp"
$LogFile = Join-Path $LogDir "Install-$Stamp.log"
$Desktop = Join-Path $ProfileRoot 'Desktop'
#endregion

#region --- Functions ---
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line } catch { }
}

function Invoke-Icacls {
    # Runs icacls.exe without letting its error text stop the script.
    # "Access is denied" on junctions such as "Application Data" is expected:
    # Windows blocks listing them on purpose. Everything is written to the log.
    param([string[]]$Arguments)
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & icacls.exe @Arguments 2>&1
        $rc  = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $eap }
    foreach ($line in $out) {
        $text = "$line".Trim()
        if ($text) { Write-Log "  icacls: $text" }
    }
    return $rc
}

function Protect-Folder {
    # Creates a folder that only SYSTEM and Administrators can access
    param([string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in 'S-1-5-18', 'S-1-5-32-544') {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            (New-Object System.Security.Principal.SecurityIdentifier $sid),
            'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    (Get-Item -LiteralPath $Path -Force).SetAccessControl($acl)
}

function Test-BadRule {
    param($Rule)
    return ($Rule.AccessControlType -eq 'Allow' -and
            $BroadSids -contains $Rule.IdentityReference.Value -and
            (([long][int]$Rule.FileSystemRights) -band $WriteMask))
}

function Get-ProfileItems {
    # Root folder + everything under it, skipping junctions/symlinks
    param([string]$Root)
    $rp = [System.IO.FileAttributes]::ReparsePoint
    @(Get-Item -LiteralPath $Root -Force) +
    @(Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { -not ($_.Attributes -band $rp) })
}

function Get-BadRules {
    param($Item)
    $sec = $Item.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
    @($sec.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]) |
        Where-Object { Test-BadRule $_ })
}

function Repair-Item {
    # Removes bad entries from one file/folder and returns the number removed.
    #
    # Works on the raw ACL, so it also handles permission lists that are
    # "not in canonical form" (entries in a non-standard order, common on old
    # images). The .NET rule methods refuse to edit those.
    #
    # The rebuilt list is put in Windows' standard order:
    #   1. explicit Deny   2. explicit Allow   3. inherited entries
    # (original order is kept within each group)
    param($Item)
    $sections = [System.Security.AccessControl.AccessControlSections]::Access
    $sec  = $Item.GetAccessControl($sections)
    $raw  = New-Object System.Security.AccessControl.RawSecurityDescriptor(
                $sec.GetSecurityDescriptorSddlForm($sections))
    $dacl = $raw.DiscretionaryAcl
    if ($null -eq $dacl) { return 0 }

    $wasCanonical  = $sec.AreAccessRulesCanonical
    $removed       = 0
    $explicitDeny  = New-Object System.Collections.Generic.List[System.Security.AccessControl.GenericAce]
    $explicitAllow = New-Object System.Collections.Generic.List[System.Security.AccessControl.GenericAce]
    $inherited     = New-Object System.Collections.Generic.List[System.Security.AccessControl.GenericAce]

    foreach ($ace in $dacl) {
        # AceFlags is a byte-based enum; PowerShell 5.1 throws "Specified cast is not valid"
        # if you -band it directly, so convert to a plain number first. 0x10 = Inherited.
        if (([int][byte]$ace.AceFlags) -band 0x10) {
            $inherited.Add($ace); continue
        }

        $isBad = ($ace -is [System.Security.AccessControl.CommonAce] -and
                  $ace.AceQualifier -eq [System.Security.AccessControl.AceQualifier]::AccessAllowed -and
                  $BroadSids -contains $ace.SecurityIdentifier.Value -and
                  (([long]$ace.AccessMask) -band $WriteMask))

        if ($isBad) {
            $removed++
            Write-Log ("  Removed {0} [mask 0x{1:X}] on {2}" -f $ace.SecurityIdentifier.Value, $ace.AccessMask, $Item.FullName)
            # If the removed entry also allowed reading, give read & execute back
            if (([long]$ace.AccessMask) -band 0x1) {
                $ro = New-Object System.Security.AccessControl.CommonAce(
                        $ace.AceFlags,
                        [System.Security.AccessControl.AceQualifier]::AccessAllowed,
                        0x1200A9,   # Read & Execute + Synchronize
                        $ace.SecurityIdentifier, $false, $null)
                $explicitAllow.Add($ro)
            }
            continue
        }

        if ($ace -is [System.Security.AccessControl.QualifiedAce] -and
            $ace.AceQualifier -eq [System.Security.AccessControl.AceQualifier]::AccessDenied) {
            $explicitDeny.Add($ace)
        }
        else { $explicitAllow.Add($ace) }
    }

    # Nothing to remove and already in standard order: leave it alone
    if ($removed -eq 0 -and $wasCanonical) { return 0 }

    $newAcl = New-Object System.Security.AccessControl.RawAcl($dacl.Revision, $dacl.Count)
    $i = 0
    foreach ($a in (@($explicitDeny) + @($explicitAllow) + @($inherited))) {
        $newAcl.InsertAce($i, $a); $i++
    }
    $raw.DiscretionaryAcl = $newAcl
    $sec.SetSecurityDescriptorSddlForm($raw.GetSddlForm($sections), $sections)
    $Item.SetAccessControl($sec)

    if (-not $wasCanonical) { Write-Log "  Put permissions back in standard order on $($Item.FullName)" }
    return $removed
}

function Remove-StrayFile {
    param($File)
    if ($QuarantineFiles) {
        $rel  = $File.FullName.Substring($ProfileRoot.Length).TrimStart('\')
        $dest = Join-Path $QDir $rel
        New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
        Move-Item -LiteralPath $File.FullName -Destination $dest -Force
        Write-Log "  Quarantined: $($File.FullName) -> $dest"
    }
    else {
        Remove-Item -LiteralPath $File.FullName -Force
        Write-Log "  Deleted: $($File.FullName)"
    }
}
#endregion

#region --- Main ---
try {
    Protect-Folder $BaseDir
    New-Item -ItemType Directory -Path $LogDir, $BkpDir -Force | Out-Null
    Write-Log "=== Default profile ACL fix v$Version starting on $env:COMPUTERNAME (user: $env:USERNAME) ==="

    if (-not (Test-Path -LiteralPath $ProfileRoot)) {
        Write-Log "$ProfileRoot not found. Nothing to do." 'ERROR'
        exit 1
    }

    # 1. Back up current permissions (root and children saved separately for restore)
    $rootBkp  = Join-Path $BkpDir "RootACL-$Stamp.txt"
    $childBkp = Join-Path $BkpDir "ChildACL-$Stamp.txt"
    $rc1 = Invoke-Icacls @($ProfileRoot, '/save', $rootBkp, '/C', '/Q')
    $rc2 = Invoke-Icacls @("$ProfileRoot\*", '/save', $childBkp, '/T', '/C', '/Q')
    if (-not (Test-Path -LiteralPath $rootBkp) -or -not (Test-Path -LiteralPath $childBkp)) {
        Write-Log 'ACL backup files were not created. Stopping without changes.' 'ERROR'
        exit 1
    }
    Write-Log "Backup saved: $rootBkp (icacls exit $rc1)"
    Write-Log "Backup saved: $childBkp (icacls exit $rc2; 'Access is denied' on junctions is expected)"

    # 2. Find and quarantine user-placed files
    Write-Log 'Scanning for user-placed files...'
    $stray = @()
    foreach ($f in (Get-ChildItem -LiteralPath $ProfileRoot -Recurse -Force -File -ErrorAction SilentlyContinue)) {
        if ($f.FullName -like "$Desktop\*" -and $f.Name -ne 'desktop.ini') { $stray += $f; continue }
        try {
            $owner = $f.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Owner).GetOwner(
                [System.Security.Principal.NTAccount]).Value
        } catch { $owner = $null }   # unresolved SIDs (old image accounts) are left alone
        if ($owner -like "$DomainNetBIOS\*") { $stray += $f }
    }
    if ($stray.Count -gt 0) {
        Write-Log "Found $($stray.Count) user-placed file(s)." 'WARN'
        foreach ($f in $stray) {
            try { Remove-StrayFile $f }
            catch { Write-Log "  Could not move $($f.FullName): $($_.Exception.Message)" 'WARN' }
        }
    }
    else { Write-Log 'No user-placed files found.' }

    # 3. Remove bad permission entries
    Write-Log 'Removing write access for broad groups...'
    $fixed = 0; $failed = 0
    foreach ($item in (Get-ProfileItems $ProfileRoot)) {
        try   { $fixed += Repair-Item $item }
        catch { $failed++; Write-Log "  FAILED on $($item.FullName): $($_.Exception.Message)" 'WARN' }
    }
    Write-Log "Entries removed: $fixed. Items that could not be changed: $failed."

    # 4. Verify
    $remaining = @(Get-ProfileItems $ProfileRoot | Where-Object {
        try { (Get-BadRules $_).Count -gt 0 } catch { $false } })
    $leftover  = @(Get-ChildItem -LiteralPath $Desktop -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'desktop.ini' })

    # Reporting marker (detection does NOT rely on this; it checks real permissions)
    New-Item -Path $RegKey -Force | Out-Null
    Set-ItemProperty -Path $RegKey -Name 'Version'        -Value $Version
    Set-ItemProperty -Path $RegKey -Name 'LastRun'        -Value (Get-Date -Format 's')
    Set-ItemProperty -Path $RegKey -Name 'EntriesRemoved' -Value $fixed
    Set-ItemProperty -Path $RegKey -Name 'FilesHandled'   -Value $stray.Count
    Set-ItemProperty -Path $RegKey -Name 'LastBackup'     -Value $childBkp

    if ($remaining.Count -gt 0 -or $leftover.Count -gt 0) {
        foreach ($i in $remaining) { Write-Log "  Still open: $($i.FullName)" 'ERROR' }
        foreach ($i in $leftover)  { Write-Log "  Still on Default desktop: $($i.FullName)" 'ERROR' }
        Write-Log '=== Finished with problems remaining (exit 1) ===' 'ERROR'
        exit 1
    }

    Write-Log '=== Finished successfully (exit 0) ==='
    exit 0
}
catch {
    Write-Log "Unexpected error: $($_.Exception.Message)" 'ERROR'
    exit 1
}
#endregion