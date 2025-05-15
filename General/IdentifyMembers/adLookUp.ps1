# Requires no extra modules (uses ADSI for domain groups)
# Run in PowerShell.exe or ISE as Admin

# --- 1) Prompt for all paths via InputBox ---
Add-Type -AssemblyName Microsoft.VisualBasic

# Folder to scan
$FolderPath = [Microsoft.VisualBasic.Interaction]::InputBox(
    "Enter the full path of the FOLDER you want to scan:",
    "Folder Path",
    ""
)
if (-not $FolderPath) {
    Write-Host "No folder path provided. Exiting."
    return
}
if (-not (Test-Path $FolderPath)) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Folder does not exist:`n$FolderPath",
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    return
}

# CSV for Group→Member
$GroupCsv = [Microsoft.VisualBasic.Interaction]::InputBox(
    "Enter the full output path for the Group→Member CSV (e.g. C:\Temp\Groups.csv):",
    "Group CSV Output",
    ""
)
if (-not $GroupCsv) {
    Write-Host "No Group CSV path provided. Exiting."
    return
}

# CSV for Member→Groups
$UserCsv = [Microsoft.VisualBasic.Interaction]::InputBox(
    "Enter the full output path for the Member→Groups CSV (e.g. C:\Temp\Users.csv):",
    "User CSV Output",
    ""
)
if (-not $UserCsv) {
    Write-Host "No User CSV path provided. Exiting."
    return
}

# Optional TXT report
$TextOutput = [Microsoft.VisualBasic.Interaction]::InputBox(
    "Optionally, enter a full path for a plain-text report (or leave blank to skip):",
    "Text Report Output",
    ""
)

# --- 2) Auto-correct directory-only paths ---
function Resolve-OutputPath {
    param(
        [string]$Path,
        [string]$DefaultName
    )
    if (Test-Path $Path -PathType Container) {
        return Join-Path $Path $DefaultName
    }
    return $Path
}

$GroupCsv   = Resolve-OutputPath $GroupCsv  'GroupMembers.csv'
$UserCsv    = Resolve-OutputPath $UserCsv   'UserMembership.csv'
if ($TextOutput) {
    $TextOutput = Resolve-OutputPath $TextOutput 'GroupMembers.txt'
}

# --- 3) Scan the folder ACL and expand groups ---
Add-Type -AssemblyName System.Windows.Forms

# helper to recursively enumerate domain groups via ADSI
function Get-DomainGroupMembers {
    param(
        [string]$DistinguishedName,
        [ref]$Seen
    )
    if (-not $Seen.Value) { $Seen.Value = @{} }
    if ($Seen.Value.ContainsKey($DistinguishedName)) { return }
    $Seen.Value[$DistinguishedName] = $true

    $grpObj = [ADSI]"LDAP://$DistinguishedName"
    foreach ($m in $grpObj.member) {
        $obj = [ADSI]"LDAP://$m"
        $classes = @($obj.objectClass)
        if ($classes -contains 'group') {
            Get-DomainGroupMembers -DistinguishedName $obj.distinguishedName -Seen $Seen
        }
        elseif ($classes -contains 'user') {
            ,$obj.sAMAccountName
        }
    }
}

$principals = Get-Acl -Path $FolderPath |
    Select-Object -ExpandProperty Access |
    Select-Object -ExpandProperty IdentityReference |
    Sort-Object -Unique

$results = foreach ($id in $principals) {
    $fullName = $id.Value
    if ($fullName -notmatch '^[^\\]+\\[^\\]+$') { continue }
    $scope, $grp = $fullName.Split('\',2)

    try {
        if ($scope -eq $env:COMPUTERNAME -or $scope -ieq 'BUILTIN') {
            # local group?
            if (-not (Get-LocalGroup -Name $grp -ErrorAction SilentlyContinue)) {
                continue
            }
            $members = Get-LocalGroupMember -Name $grp -ErrorAction Stop |
                       Where-Object ObjectClass -eq 'User' |
                       Select-Object -ExpandProperty Name
        }
        else {
            # domain group via ADSI
            # find group DN
            $root   = [ADSI]"LDAP://RootDSE"
            $base   = [ADSI]"LDAP://$($root.defaultNamingContext)"
            $ds     = New-Object System.DirectoryServices.DirectorySearcher($base)
            $ds.Filter = "(&(objectCategory=group)(sAMAccountName=$grp))"
            $entry  = $ds.FindOne()
            if (-not $entry) { continue }
            $seen = [ref]@{}
            $members = Get-DomainGroupMembers -DistinguishedName $entry.Properties.distinguishedName[0] -Seen $seen
        }
    }
    catch {
        # wrap var to avoid the ":" parsing issue
        Write-Warning "Failed to enumerate ${fullName}: $_"
        continue
    }

    foreach ($user in $members) {
        [PSCustomObject]@{ Group = $fullName; Member = $user }
    }
}

# --- 4) Export outputs ---
$results | Export-Csv -Path $GroupCsv -NoTypeInformation -Encoding UTF8
Write-Host "Wrote $($results.Count) rows to Group→Member CSV:`n  $GroupCsv"

$results |
  Group-Object -Property Member |
  ForEach-Object {
      [PSCustomObject]@{
          Member = $_.Name
          Groups = ($_.Group | Sort-Object) -join ';'
      }
  } |
  Export-Csv -Path $UserCsv -NoTypeInformation -Encoding UTF8
Write-Host "Wrote $((Import-Csv $UserCsv).Count) users to Member→Groups CSV:`n  $UserCsv"

if ($TextOutput) {
    $results |
      ForEach-Object { "$($_.Group) : $($_.Member)" } |
      Out-File -FilePath $TextOutput -Encoding UTF8
    Write-Host "Wrote plain-text report:`n  $TextOutput"
}

# --- 5) Final confirmation popup ---
$body  = "Completed successfully!`n`n"
$body += "Group→Member CSV:`n  $GroupCsv`n`n"
$body += "Member→Groups CSV:`n  $UserCsv"
if ($TextOutput) { $body += "`n`nText report:`n  $TextOutput" }

[System.Windows.Forms.MessageBox]::Show(
    $body,
    "Done!",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
)
