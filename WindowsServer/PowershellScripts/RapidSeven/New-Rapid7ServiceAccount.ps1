#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Creates and configures a Rapid7 InsightVM service account in Active Directory
    with the minimum permissions needed for authenticated vulnerability scanning.

.DESCRIPTION
    Per Rapid7 best practices, this script creates a dedicated service account with:
      - Domain Users membership (base)
      - Local Administrators group on target machines (via GPO is preferred, but
        this script can add to local admin on individual machines)
      - Password never expires (service account)
      - Account description and metadata for audit trail

    The Rapid7 docs recommend a domain admin or local admin account for the most
    exhaustive scan results. This script creates a dedicated service account
    rather than reusing an existing admin account (least-privilege principle).

    IMPORTANT: After creating the account, you still need to:
      1. Add the account to Local Administrators on target machines (GPO recommended)
      2. Set the UAC registry key if using local admin (see notes)

.PARAMETER AccountName
    The sAMAccountName for the service account. Default: svc-rapid7-scan

.PARAMETER DisplayName
    Display name in AD. Default: Rapid7 InsightVM Scanner

.PARAMETER OUPath
    Distinguished Name of the OU to create the account in.
    Default: Auto-detects service accounts OU.

.PARAMETER AddToLocalAdmin
    If specified, also adds the service account to the local Administrators
    group on target machines via Invoke-Command.

.PARAMETER TargetComputers
    List of computers to add the service account to local Administrators.
    Only used with -AddToLocalAdmin.

.EXAMPLE
    # Create the service account (will prompt for password)
    .\New-Rapid7ServiceAccount.ps1

.EXAMPLE
    # Create and add to local admin on specific machines
    .\New-Rapid7ServiceAccount.ps1 -AddToLocalAdmin -TargetComputers "LIBWS001","LIBWS002"

.NOTES
    Author:     Oji McLeod - UMD Libraries IT
    Reference:  https://docs.rapid7.com/insightvm/authentication-on-windows-best-practices/
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$AccountName = "svc-rapid7-scan",
    [string]$DisplayName = "Rapid7 InsightVM Scanner - Library IT",

    [string]$OUPath,  # Set to your service accounts OU, e.g.:
                       # "OU=Service Accounts,OU=Library IT,DC=ad,DC=umd,DC=edu"

    [switch]$AddToLocalAdmin,

    [string[]]$TargetComputers
)

#region --- Pre-flight Checks ---
Write-Host "`n=== Rapid7 InsightVM Service Account Setup ===" -ForegroundColor Cyan
Write-Host "Domain: $env:USERDNSDOMAIN" -ForegroundColor Cyan
Write-Host "Account: $AccountName" -ForegroundColor Cyan
Write-Host ""

# Check if running with appropriate privileges
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script should be run as Administrator for local admin group changes."
}

# Check if account already exists
$existingAccount = Get-ADUser -Filter "SamAccountName -eq '$AccountName'" -ErrorAction SilentlyContinue
if ($existingAccount) {
    Write-Warning "Account '$AccountName' already exists in AD."
    Write-Host "DN: $($existingAccount.DistinguishedName)" -ForegroundColor Yellow
    Write-Host ""

    $continue = Read-Host "Skip account creation and proceed to local admin setup? (Y/N)"
    if ($continue -ne 'Y') {
        Write-Host "Exiting." -ForegroundColor Yellow
        return
    }
    $ServiceAccount = $existingAccount
}
#endregion

#region --- Create AD Service Account ---
if (-not $existingAccount) {
    # Prompt for password securely
    $Password = Read-Host -AsSecureString "Enter password for $AccountName"
    $PasswordConfirm = Read-Host -AsSecureString "Confirm password"

    # Convert to plaintext for comparison only
    $BSTR1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $BSTR2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($PasswordConfirm)
    $Plain1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR1)
    $Plain2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR2)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR1)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR2)

    if ($Plain1 -ne $Plain2) {
        Write-Error "Passwords do not match. Exiting."
        return
    }
    # Clear plaintext from memory
    $Plain1 = $null
    $Plain2 = $null

    # Auto-detect OU if not specified
    if (-not $OUPath) {
        Write-Warning "No OU specified. You should set -OUPath to your service accounts OU."
        Write-Host "Example: -OUPath 'OU=Service Accounts,OU=Library IT,DC=ad,DC=umd,DC=edu'" -ForegroundColor Yellow
        Write-Host ""
        $OUPath = Read-Host "Enter the target OU Distinguished Name"
        if (-not $OUPath) {
            Write-Error "OU path is required. Exiting."
            return
        }
    }

    $AccountParams = @{
        Name                  = $AccountName
        SamAccountName        = $AccountName
        UserPrincipalName     = "$AccountName@ad.umd.edu"
        DisplayName           = $DisplayName
        Description           = "Service account for DIT Rapid7 InsightVM authenticated vulnerability scanning. Do not disable without coordinating with DIT security team."
        Path                  = $OUPath
        AccountPassword       = $Password
        Enabled               = $true
        PasswordNeverExpires  = $true
        CannotChangePassword  = $false
        ChangePasswordAtLogon = $false
    }

    if ($PSCmdlet.ShouldProcess($AccountName, "Create AD service account")) {
        try {
            New-ADUser @AccountParams -ErrorAction Stop
            Write-Host "[OK] Service account '$AccountName' created successfully." -ForegroundColor Green

            $ServiceAccount = Get-ADUser -Identity $AccountName
            Write-Host "     DN: $($ServiceAccount.DistinguishedName)" -ForegroundColor Gray
        }
        catch {
            Write-Error "Failed to create service account: $($_.Exception.Message)"
            return
        }
    }
}
#endregion

#region --- UAC Registry Key Reminder ---
Write-Host "`n--- UAC Registry Key (Required for local admin scanning) ---" -ForegroundColor Yellow
Write-Host @"

  Per Rapid7 docs, if using a local admin account with UAC, you must set:

    Registry Key:  HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
    Value Name:    LocalAccountTokenFilterPolicy
    Value Type:    DWORD
    Value Data:    1

  PowerShell (run on each target, or deploy via GPO/Intune):

    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' ``
        -Name 'LocalAccountTokenFilterPolicy' -Value 1 -Type DWord

  NOTE: This may not be needed if using a DOMAIN admin account, but is required
        for local admin accounts to bypass UAC remote restrictions.

"@ -ForegroundColor Gray
#endregion

#region --- Add to Local Administrators on Target Machines ---
if ($AddToLocalAdmin -and $TargetComputers) {
    Write-Host "`n--- Adding to Local Administrators ---" -ForegroundColor Cyan

    $DomainPrefix = ($env:USERDNSDOMAIN -split '\.')[0].ToUpper()  # e.g., "AD"
    $FullAccount = "$DomainPrefix\$AccountName"

    foreach ($Computer in $TargetComputers) {
        Write-Host "  Target: $Computer ... " -NoNewline

        if ($PSCmdlet.ShouldProcess($Computer, "Add $FullAccount to local Administrators")) {
            try {
                Invoke-Command -ComputerName $Computer -ScriptBlock {
                    param($Account)
                    Add-LocalGroupMember -Group "Administrators" -Member $Account -ErrorAction Stop
                } -ArgumentList $FullAccount -ErrorAction Stop

                Write-Host "OK" -ForegroundColor Green
            }
            catch {
                if ($_.Exception.Message -match "already a member") {
                    Write-Host "ALREADY MEMBER" -ForegroundColor Yellow
                }
                else {
                    Write-Host "FAILED - $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
}
elseif ($AddToLocalAdmin -and -not $TargetComputers) {
    Write-Warning "-AddToLocalAdmin requires -TargetComputers. Skipping local admin setup."
}
#endregion

#region --- Summary & Next Steps ---
Write-Host "`n$('=' * 60)" -ForegroundColor Green
Write-Host "  SETUP COMPLETE - NEXT STEPS" -ForegroundColor Green
Write-Host "$('=' * 60)" -ForegroundColor Green
Write-Host @"

  1. ADD TO LOCAL ADMINS (if not done above):
     Preferred: Create a GPO that adds '$AccountName' to the local
     Administrators group on all library workstations/servers.

     GPO Path: Computer Configuration > Preferences > Control Panel Settings
               > Local Users and Groups > Administrators (built-in)
               > Add: AD\$AccountName

  2. VERIFY REMOTE ACCESS:
     From a target machine, test that the account can authenticate:

       runas /user:AD\$AccountName "cmd /c whoami"

  3. VERIFY WMI ACCESS (critical for Rapid7 scans):

       # Run from a machine where the service account has admin rights
       Get-WmiObject -Class Win32_OperatingSystem -ComputerName <TARGET> ``
           -Credential (Get-Credential AD\$AccountName)

  4. ENSURE REMOTE REGISTRY (if using CIFS instead of WMI):
     The Remote Registry service must be running on scan targets:

       Get-Service -Name RemoteRegistry -ComputerName <TARGET>
       Set-Service -Name RemoteRegistry -StartupType Automatic -ComputerName <TARGET>
       Start-Service -Name RemoteRegistry -ComputerName <TARGET>

  5. PROVIDE CREDENTIALS TO DIT:
     Send the account name and password to the DIT security team
     via a secure channel (NOT email). Use a password manager or
     encrypted file transfer.

     Account:  AD\$AccountName
     UPN:      $AccountName@ad.umd.edu

  6. FIREWALL RULES:
     Run Deploy-Rapid7FirewallRules.ps1 to open the scanning subnet
     (128.8.236.64/27) on all managed Windows hosts.

"@ -ForegroundColor White
#endregion