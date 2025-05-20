# ————————————————————————————————————————————————
# Script: Export-ADGroupMembersWithPrompt.ps1
# Description:  Prompt for an AD group, query a hardcoded DC, and export members to CSV with minimal prompts
# Requires: RSAT ActiveDirectory module
# ————————————————————————————————————————————————

# 1) Load the AD module and VB assemblies
Import-Module ActiveDirectory -ErrorAction Stop
Add-Type -AssemblyName Microsoft.VisualBasic, System.Windows.Forms

# 2) Hardcode your domain controller and default export directory
$ServerName   = 'OITDC004.AD.UMD.EDU'
$ExportFolder = 'C:\Exports'

# 3) Create or update the AD PSDrive to avoid default-drive warnings
if (-not (Get-PSDrive -Name AD -ErrorAction SilentlyContinue)) {
    try {
        New-PSDrive -Name AD -PSProvider ActiveDirectory -Root "" -Server $ServerName -ErrorAction Stop | Out-Null
    }
    catch {
        # Use format operator to avoid variable parsing issues
        Write-Warning ([string]::Format("Unable to create AD PSDrive on server {0}: {1}", $ServerName, $_.Exception.Message))
    }
}

# 4) Ensure export directory exists
if (-not (Test-Path $ExportFolder)) {
    New-Item -Path $ExportFolder -ItemType Directory -Force | Out-Null
}

# 5) Prompt once for the AD group name
$GroupName = [Microsoft.VisualBasic.Interaction]::InputBox(
    'Enter the AD group name (sAMAccountName, CN, or DN):',
    'Select AD Group',
    ''
)

if ([string]::IsNullOrWhiteSpace($GroupName)) {
    [System.Windows.Forms.MessageBox]::Show(
        'No group specified. Exiting.',
        'Canceled',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Exclamation
    )
    exit 1
}

# 6) Build the CSV file path based on the group name
$SafeName = ($GroupName -replace '[\\/:*?"<>|]', '_')
$CsvPath  = Join-Path $ExportFolder "$SafeName`_Members.csv"

# 7) Retrieve members from the specified DC and export
try {
    $Members = Get-ADGroupMember -Identity $GroupName -Server $ServerName -Recursive -ErrorAction Stop |
        Where-Object { $_.ObjectClass -eq 'user' } |
        Get-ADUser -Server $ServerName -Properties DisplayName, EmailAddress |
        Select-Object @{Name='SamAccountName';Expression={$_.SamAccountName}},
                      @{Name='Name';        Expression={$_.Name}},
                      @{Name='DisplayName'; Expression={$_.DisplayName}},
                      @{Name='Email';       Expression={$_.EmailAddress}}

    $Members | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

    [System.Windows.Forms.MessageBox]::Show(
        ("Export successful: {0} users`n{1}" -f $Members.Count, $CsvPath),
        'Done',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}
catch {
    [System.Windows.Forms.MessageBox]::Show(
        ("Error exporting group members:`n{0}" -f $_.Exception.Message),
        'Export Failed',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}
