#Requires -Version 5.1
<#
.SYNOPSIS
    Creates and configures a local Rapid7 InsightVM service account with the
    minimum permissions needed for authenticated vulnerability scanning.

.DESCRIPTION
    This script creates a dedicated local admin account on the current machine
    for Rapid7 InsightVM scanning. It handles:
      - Local account creation with a secure password
      - Administrators group membership
      - UAC registry key (LocalAccountTokenFilterPolicy) so remote scans
        can authenticate without being stripped of admin rights

    Run this script manually on each VM that DIT will scan.

.PARAMETER AccountName
    Name for the local service account. Must be alphanumeric, hyphens, or
    underscores only. Default: LIBR-InsightVM

.PARAMETER DisplayName
    Full name / display name for the local account.
    Default: Rapid7 InsightVM Scanner - Library IT

.PARAMETER Remove
    Removes the service account, its Administrators membership, and reverts
    the LocalAccountTokenFilterPolicy registry key.

.EXAMPLE
    # Create the service account (will prompt for password)
    .\New-Rapid7ServiceAccount.ps1

.EXAMPLE
    # Preview changes without applying
    .\New-Rapid7ServiceAccount.ps1 -WhatIf

.EXAMPLE
    # Remove the account and undo registry changes
    .\New-Rapid7ServiceAccount.ps1 -Remove

.NOTES
    Author:     Oji McLeod - UMD Libraries IT
    Date:       2026-03-02
    Version:    2.0
    Reference:  https://docs.rapid7.com/insightvm/authentication-on-windows-best-practices/
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-zA-Z0-9\-_]+$')]
    [string]$AccountName = "LIBR-InsightVM",

    [string]$DisplayName = "Rapid7 InsightVM Scanner - Library IT",

    [switch]$Remove
)

begin {
    $ErrorActionPreference = 'Stop'

    $RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $RegistryName = 'LocalAccountTokenFilterPolicy'
    $Description  = "Account for InsightVM vulnerability scanning."

    #region --- Pre-flight Checks ---
    Write-Host "`n=== Rapid7 InsightVM Local Service Account Setup ===" -ForegroundColor Cyan
    Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
    Write-Host "Account:  $AccountName" -ForegroundColor Cyan
    Write-Host ""

    # Elevation is required for local user/group/registry changes
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This script must be run as Administrator. Right-click PowerShell > Run as Administrator."
        return
    }
    #endregion
}

process {
    #region --- Remove Mode ---
    if ($Remove) {
        Write-Host "--- Remove Mode ---" -ForegroundColor Yellow

        # Remove from Administrators group
        $members = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
        if ($members.Name -match [regex]::Escape($AccountName)) {
            if ($PSCmdlet.ShouldProcess($AccountName, "Remove from local Administrators group")) {
                try {
                    Remove-LocalGroupMember -Group "Administrators" -Member $AccountName -ErrorAction Stop
                    Write-Host "[OK] Removed '$AccountName' from Administrators." -ForegroundColor Green
                }
                catch {
                    Write-Warning "Could not remove from Administrators: $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-Host "[--] '$AccountName' is not in Administrators. Skipping." -ForegroundColor Gray
        }

        # Remove the local account
        $existing = Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue
        if ($existing) {
            if ($PSCmdlet.ShouldProcess($AccountName, "Remove local user account")) {
                try {
                    Remove-LocalUser -Name $AccountName -ErrorAction Stop
                    Write-Host "[OK] Local account '$AccountName' removed." -ForegroundColor Green
                }
                catch {
                    Write-Error "Failed to remove account: $($_.Exception.Message)"
                    return
                }
            }
        }
        else {
            Write-Host "[--] Account '$AccountName' does not exist. Skipping." -ForegroundColor Gray
        }

        # Revert registry key
        $currentValue = Get-ItemProperty -Path $RegistryPath -Name $RegistryName -ErrorAction SilentlyContinue
        if ($null -ne $currentValue -and $currentValue.$RegistryName -eq 1) {
            if ($PSCmdlet.ShouldProcess($RegistryName, "Revert registry key to 0")) {
                Set-ItemProperty -Path $RegistryPath -Name $RegistryName -Value 0 -Type DWord -Force
                Write-Host "[OK] Registry key '$RegistryName' reverted to 0." -ForegroundColor Green
            }
        }
        else {
            Write-Host "[--] Registry key already absent or set to 0. Skipping." -ForegroundColor Gray
        }

        Write-Host "`nRemoval complete.`n" -ForegroundColor Green
        return
    }
    #endregion

    #region --- Password Prompt ---
    $Password = Read-Host -AsSecureString "Enter password for $AccountName"
    $PasswordConfirm = Read-Host -AsSecureString "Confirm password"

    $plain1 = [System.Net.NetworkCredential]::new('', $Password).Password
    $plain2 = [System.Net.NetworkCredential]::new('', $PasswordConfirm).Password

    if ($plain1 -ne $plain2) {
        Write-Error "Passwords do not match. Exiting."
        return
    }
    Remove-Variable plain1, plain2
    #endregion

    #region --- Create or Verify Local Account ---
    $existingAccount = Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue

    if ($existingAccount) {
        Write-Warning "Local account '$AccountName' already exists on $env:COMPUTERNAME."
        if (-not $PSCmdlet.ShouldContinue(
            "Account '$AccountName' already exists. Skip creation and ensure Administrators membership?",
            "Account Exists"
        )) {
            Write-Host "Exiting." -ForegroundColor Yellow
            return
        }
    }
    else {
        if ($PSCmdlet.ShouldProcess($AccountName, "Create local service account")) {
            try {
                $userParams = @{
                    Name                 = $AccountName
                    Password             = $Password
                    FullName             = $DisplayName
                    Description          = $Description
                    PasswordNeverExpires = $true
                    AccountNeverExpires  = $true
                    UserMayNotChangePassword = $false
                }
                New-LocalUser @userParams -ErrorAction Stop | Out-Null
                Write-Host "[OK] Local account '$AccountName' created." -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to create local account: $($_.Exception.Message)"
                return
            }
        }
    }
    #endregion

    #region --- Add to Local Administrators ---
    if ($PSCmdlet.ShouldProcess($AccountName, "Add to local Administrators group")) {
        try {
            Add-LocalGroupMember -Group "Administrators" -Member $AccountName -ErrorAction Stop
            Write-Host "[OK] '$AccountName' added to Administrators." -ForegroundColor Green
        }
        catch {
            if ($_.Exception.Message -match "already a member") {
                Write-Host "[OK] '$AccountName' is already in Administrators." -ForegroundColor Yellow
            }
            else {
                Write-Error "Failed to add to Administrators: $($_.Exception.Message)"
                return
            }
        }
    }
    #endregion

    #region --- Set UAC Registry Key ---
    if ($PSCmdlet.ShouldProcess($RegistryName, "Set registry key to 1 (allow remote admin for local accounts)")) {
        try {
            if (-not (Test-Path $RegistryPath)) {
                New-Item -Path $RegistryPath -Force | Out-Null
            }
            Set-ItemProperty -Path $RegistryPath -Name $RegistryName -Value 1 -Type DWord -Force
            Write-Host "[OK] Registry key '$RegistryName' set to 1." -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to set registry key: $($_.Exception.Message)"
            return
        }
    }
    #endregion
}

end {
    # Skip summary if we were in Remove mode (already returned)
    if ($Remove) { return }

    #region --- Verification ---
    Write-Host "`n--- Verification ---" -ForegroundColor Cyan

    # Account info
    $acct = Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue
    if ($acct) {
        Write-Host "  Account:  $($acct.Name)" -ForegroundColor White
        Write-Host "  Enabled:  $($acct.Enabled)" -ForegroundColor White
        Write-Host "  FullName: $($acct.FullName)" -ForegroundColor White
    }

    # Administrators membership
    $adminMembers = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
    $isMember = $adminMembers | Where-Object { $_.Name -match [regex]::Escape($AccountName) }
    if ($isMember) {
        Write-Host "  Admins:   YES" -ForegroundColor Green
    }
    else {
        Write-Host "  Admins:   NO (check manually)" -ForegroundColor Red
    }

    # Registry key
    $regValue = Get-ItemProperty -Path $RegistryPath -Name $RegistryName -ErrorAction SilentlyContinue
    if ($null -ne $regValue) {
        Write-Host "  $RegistryName = $($regValue.$RegistryName)" -ForegroundColor White
    }
    #endregion

    #region --- Next Steps ---
    Write-Host "`n$('=' * 60)" -ForegroundColor Green
    Write-Host "  SETUP COMPLETE - NEXT STEPS" -ForegroundColor Green
    Write-Host "$('=' * 60)" -ForegroundColor Green
    Write-Host @"

  1. VERIFY WMI ACCESS (critical for Rapid7 scans):

       Get-WmiObject -Class Win32_OperatingSystem -Credential `
           (Get-Credential $AccountName)

  2. PROVIDE CREDENTIALS TO DIT:
     Send the account name and password to the DIT security team
     via a secure channel (NOT email). Use a password manager or
     encrypted file transfer.

       Computer: $env:COMPUTERNAME
       Account:  $AccountName

  3. FIREWALL RULES:
     Run Deploy-Rapid7FirewallRules.ps1 to open the scanning subnet
     (128.8.236.64/27) on this host.

"@ -ForegroundColor White
    #endregion
}
