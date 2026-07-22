<#
.SYNOPSIS
    Creates the libguest1-500 local accounts and maps them to UMD.EDU Kerberos
    principals so patrons can log on with passwords issued through SIMS.

.DESCRIPTION
    Self-contained replacement for the old libguestcreation.bat + kerberos.reg +
    libguest.vbs combo. Reads libguest.txt from the folder this script runs from,
    so it has no network-share dependency. Safe to re-run (idempotent).

    Must run as SYSTEM or an elevated administrator (writes HKLM and local SAM).

.NOTES
    Intune Win32 install command:
      %windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-LibGuestAccounts.ps1
#>

$ErrorActionPreference = 'Stop'

$LogDir  = Join-Path $env:ProgramData 'LibGuestCreation'
$LogFile = Join-Path $LogDir 'install.log'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Start-Transcript -Path $LogFile -Append | Out-Null

$Realm       = 'UMD.EDU'
$DomainsKey  = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Domains\$Realm"
$UserListKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\UserList'
$AccountFile = Join-Path $PSScriptRoot 'libguest.txt'
$Failures    = 0

# The local SAM password is never used for interactive logon (Kerberos UserList
# mapping sends the typed password to the UMD.EDU KDCs instead), so each account
# gets a long random throwaway password rather than a shared hardcoded one.
function New-RandomPassword {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    # Base64 of 32 random bytes = 44 chars; prefix guarantees complexity classes.
    return 'Lg1!' + [Convert]::ToBase64String($bytes)
}

try {
    if (-not (Test-Path $AccountFile)) {
        throw "Account list not found: $AccountFile"
    }
    $Accounts = Get-Content $AccountFile | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }
    Write-Output "Loaded $($Accounts.Count) account names from libguest.txt"

    # Register UMD.EDU as a Kerberos realm (KDCs located via DNS SRV records).
    # Replaces kerberos.reg.
    if (-not (Test-Path $DomainsKey)) {
        New-Item -Path $DomainsKey -Force | Out-Null
        Write-Output "Created realm key: $DomainsKey"
    }
    if (-not (Test-Path $UserListKey)) {
        New-Item -Path $UserListKey -Force | Out-Null
    }

    $UsersGroup = Get-LocalGroup -SID 'S-1-5-32-545'   # built-in Users, locale-proof

    foreach ($Name in $Accounts) {
        try {
            $existing = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
            if (-not $existing) {
                $pw = ConvertTo-SecureString (New-RandomPassword) -AsPlainText -Force
                New-LocalUser -Name $Name -Password $pw `
                    -Description 'Library Local Guest Account' `
                    -UserMayNotChangePassword -PasswordNeverExpires -AccountNeverExpires | Out-Null
                Write-Output "Created local account: $Name"
            }

            # Membership in Users grants the 'Allow log on locally' right.
            if (-not (Get-LocalGroupMember -Group $UsersGroup -Member $Name -ErrorAction SilentlyContinue)) {
                Add-LocalGroupMember -Group $UsersGroup -Member $Name
            }

            # Map the Kerberos principal to the local account.
            New-ItemProperty -Path $UserListKey -Name "$Name@$Realm" -Value $Name `
                -PropertyType String -Force | Out-Null
        }
        catch {
            $Failures++
            Write-Output "FAILED on ${Name}: $($_.Exception.Message)"
        }
    }

    if ($Failures -gt 0) {
        Write-Output "Completed with $Failures failure(s)."
        Stop-Transcript | Out-Null
        exit 1
    }
    Write-Output 'Completed successfully.'
    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Output "FATAL: $($_.Exception.Message)"
    Stop-Transcript | Out-Null
    exit 1
}
