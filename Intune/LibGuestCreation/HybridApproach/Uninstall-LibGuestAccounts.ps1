<#
.SYNOPSIS
    Removes the libguest local accounts, their Kerberos UserList mappings, the
    UMD.EDU realm key, and any leftover libguest user profiles.

.NOTES
    Intune Win32 uninstall command:
      %windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-LibGuestAccounts.ps1
#>

$ErrorActionPreference = 'Continue'

$LogDir  = Join-Path $env:ProgramData 'LibGuestCreation'
$LogFile = Join-Path $LogDir 'uninstall.log'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Start-Transcript -Path $LogFile -Append | Out-Null

$Realm       = 'UMD.EDU'
$DomainsKey  = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Domains\$Realm"
$UserListKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\UserList'
# Same dual-mode lookup as the install script (command-line vs pasted script).
$ScriptDir   = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$AccountFile = Join-Path $ScriptDir 'libguest.txt'

$Accounts = Get-Content $AccountFile | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }

foreach ($Name in $Accounts) {
    Remove-ItemProperty -Path $UserListKey -Name "$Name@$Realm" -ErrorAction SilentlyContinue

    $user = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
    if ($user) {
        # Remove any on-disk profile first, then the account.
        Get-CimInstance Win32_UserProfile -Filter "SID='$($user.SID.Value)'" -ErrorAction SilentlyContinue |
            Remove-CimInstance -ErrorAction SilentlyContinue
        Remove-LocalUser -Name $Name
        Write-Output "Removed account: $Name"
    }
}

Remove-Item -Path $DomainsKey -Force -ErrorAction SilentlyContinue
Write-Output 'Uninstall complete.'
Stop-Transcript | Out-Null
exit 0
