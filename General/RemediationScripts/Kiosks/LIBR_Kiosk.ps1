<#
.SYNOPSIS
    Configures Windows automatic logon with multiple password update methods, device lock removal, and comprehensive error handling.

.DESCRIPTION
    This script provides a robust solution for configuring Windows auto-logon by:
    - Removing DeviceLock registry keys that could prevent auto-logon
    - Attempting multiple methods to update the user password and expiration settings:
      * ADSI (Active Directory Service Interfaces)
      * PowerShell local user commands
      * Traditional net user commands with CIM cmdlets (Windows 24H2 compatible)
    - Configuring secure auto-logon using LSA (Local Security Authority)
    - Adding the ".\" prefix to ensure local account usage
    - Providing detailed logging and error reporting
    - Supporting optional auto-logon count limitation

.PARAMETER user
    The username for automatic logon (local account name without ".\" prefix)

.PARAMETER pass
    The password for automatic logon

.PARAMETER AutoLogonCount
    Optional. Number of times to auto-logon (0 for unlimited)
    Default: "0"

.EXAMPLE
    set-autologon -user "kiosk" -pass "YourPassword" -AutoLogonCount "0"
    # Sets up unlimited auto-logon for local kiosk account

.EXAMPLE
    set-autologon -user "demo" -pass "Demo123!" -AutoLogonCount "5"
    # Configures auto-logon to work only for the next 5 reboots

.NOTES
    Security Warning: 
    - Auto-logon stores credentials on the system and automatically logs in
    - Only use in controlled environments (kiosks, demos, labs)
    - Physical access to the machine grants system access
    - Consider using Group Policy for enterprise environments

    Requirements:
    - Administrative privileges
    - Local account (domain accounts not recommended)
    - Windows 10/11 compatible
    - Windows 24H2 compatible (uses CIM cmdlets instead of deprecated WMIC)
#>

Write-Host "Starting auto-logon configuration..." -ForegroundColor Cyan

function set-autologon {
    param(
        [Parameter(Mandatory=$true,
                   HelpMessage="Local account username without .\ prefix")]
        [string]$user,
        
        [Parameter(Mandatory=$true,
                   HelpMessage="Account password")]
        [string]$pass,

        [Parameter(Mandatory=$false,
                   HelpMessage="Number of auto-logons (0 for unlimited)")]
        [string]$AutoLogonCount = "0"
    )

    # Define the main registry path for Windows logon settings
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
	
	# Check for existing auto-logon registry entries
    $existingSettings = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
    
    if ($existingSettings.DefaultPassword -or $existingSettings.DefaultUserName) {
        Write-Host "WARNING: Existing auto-logon configuration detected." -ForegroundColor Yellow
        Write-Host "Removing existing settings..." -ForegroundColor Yellow
        
        if ($existingSettings.DefaultPassword) {
            Remove-ItemProperty -Path $RegPath -Name "DefaultPassword" -ErrorAction SilentlyContinue
        }
        if ($existingSettings.DefaultUserName) {
            Remove-ItemProperty -Path $RegPath -Name "DefaultUserName" -ErrorAction SilentlyContinue
        }
        if ($existingSettings.DefaultDomainName) {
            Remove-ItemProperty -Path $RegPath -Name "DefaultDomainName" -ErrorAction SilentlyContinue
        }
    }
    
    # Remove DeviceLock registry keys that might prevent auto-logon
    Write-Host "Removing DeviceLock registry keys..."
    
    # Get all enrollment IDs (properly using PSChildName)
    $enrollmentIDs = (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\' -ErrorAction SilentlyContinue).PSChildName
    Write-Host "Found enrollment IDs: $($enrollmentIDs -join ', ')" -ForegroundColor Cyan

    # Remove provider-specific DeviceLock keys for each enrollment ID
    foreach ($id in $enrollmentIDs) {
        $deviceLockKey = "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$id\default\Device\DeviceLock"
        Write-Host "Removing enrollment-specific DeviceLock key: $deviceLockKey" -ForegroundColor Yellow
        Remove-Item $deviceLockKey -Force -Verbose -Recurse -ErrorAction SilentlyContinue
    }

    # Remove common DeviceLock keys
    $commonKeys = @(
        'HKLM:\SYSTEM\CurrentControlSet\Control\EAS'
        'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeviceLock'
    )
    foreach ($key in $commonKeys) {
        Write-Host "Removing common DeviceLock key: $key" -ForegroundColor Yellow
        Remove-Item $key -Force -Verbose -Recurse -ErrorAction SilentlyContinue
    }

    # Function to update password using ADSI
    function Update-UserPasswordADSI {
        try {
            Write-Host "Attempting ADSI method..."
            $computer = [ADSI]"WinNT://$env:COMPUTERNAME"
            $userObj = $computer.Children.Find($user, 'user')
            $userObj.SetPassword($pass)
            $userObj.UserFlags = 65536  # Sets PASSWORD_NEVER_EXPIRES flag
            $userObj.SetInfo()
            Write-Host "ADSI method successful" -ForegroundColor Green
            return $true
        } catch {
            Write-Host "ADSI method failed: $_" -ForegroundColor Yellow
            return $false
        }
    }

    # Function to update password using PowerShell commands
    function Update-UserPasswordPowerShell {
        try {
            Write-Host "Attempting PowerShell method..."
            $SecurePass = ConvertTo-SecureString $pass -AsPlainText -Force
            Set-LocalUser -Name $user -Password $SecurePass
            Set-LocalUser -Name $user -PasswordNeverExpires $true
            Write-Host "PowerShell method successful" -ForegroundColor Green
            return $true
        } catch {
            Write-Host "PowerShell method failed: $_" -ForegroundColor Yellow
            return $false
        }
    }

    # Function to update password using net commands with CIM cmdlets (Windows 24H2 compatible)
    function Update-UserPasswordNetCommands {
        try {
            Write-Host "Attempting net user commands..."
            $netUserResult = cmd.exe /c "net user $user $pass"
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Net user password update failed" -ForegroundColor Yellow
                return $false
            }
            
            # Use CIM cmdlets instead of deprecated WMIC (Windows 24H2 compatible)
            Write-Host "Setting password expiration using CIM cmdlets..."
            try {
                $userAccount = Get-CimInstance -ClassName Win32_UserAccount -Filter "Name='$user' AND LocalAccount=True" -ErrorAction Stop
                if ($userAccount) {
                    Set-CimInstance -InputObject $userAccount -Property @{PasswordExpires=$false} -ErrorAction Stop
                    Write-Host "Password expiration disabled via CIM cmdlets" -ForegroundColor Green
                } else {
                    Write-Host "User account not found via CIM" -ForegroundColor Yellow
                    return $false
                }
            } catch {
                Write-Host "CIM method failed: $_" -ForegroundColor Yellow
                return $false
            }
            
            Write-Host "Net user commands successful" -ForegroundColor Green
            return $true
        } catch {
            Write-Host "Net user commands failed: $_" -ForegroundColor Yellow
            return $false
        }
    }

    # Try each password update method in sequence
    $passwordUpdated = $false
    if (Update-UserPasswordADSI) {
        $passwordUpdated = $true
    } elseif (Update-UserPasswordPowerShell) {
        $passwordUpdated = $true
    } elseif (Update-UserPasswordNetCommands) {
        $passwordUpdated = $true
    }

    if (-not $passwordUpdated) {
        Write-Host "All password update methods failed!" -ForegroundColor Red
        return $false
    }

    # Import LSA utilities for secure password storage
    Write-Host "Importing LSA utilities..."
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    using System.Text;
    
    namespace PInvoke.LSAUtil {
        public class LSAutil {
            [StructLayout (LayoutKind.Sequential)]
            private struct LSA_UNICODE_STRING {
                public UInt16 Length;
                public UInt16 MaximumLength;
                public IntPtr Buffer;
            }
    
            [StructLayout (LayoutKind.Sequential)]
            private struct LSA_OBJECT_ATTRIBUTES {
                public int Length;
                public IntPtr RootDirectory;
                public LSA_UNICODE_STRING ObjectName;
                public uint Attributes;
                public IntPtr SecurityDescriptor;
                public IntPtr SecurityQualityOfService;
            }
    
            private enum LSA_AccessPolicy : long {
                POLICY_CREATE_SECRET = 0x00000020L
            }
    
            [DllImport ("advapi32.dll", SetLastError = true, PreserveSig = true)]
            private static extern uint LsaStorePrivateData (
                IntPtr policyHandle,
                ref LSA_UNICODE_STRING KeyName,
                ref LSA_UNICODE_STRING PrivateData
            );
    
            [DllImport ("advapi32.dll", SetLastError = true, PreserveSig = true)]
            private static extern uint LsaOpenPolicy (
                ref LSA_UNICODE_STRING SystemName,
                ref LSA_OBJECT_ATTRIBUTES ObjectAttributes,
                uint DesiredAccess,
                out IntPtr PolicyHandle
            );
    
            [DllImport ("advapi32.dll", SetLastError = true, PreserveSig = true)]
            private static extern uint LsaNtStatusToWinError (uint status);
    
            [DllImport ("advapi32.dll", SetLastError = true, PreserveSig = true)]
            private static extern uint LsaClose (IntPtr policyHandle);
    
            private LSA_OBJECT_ATTRIBUTES objectAttributes;
            private LSA_UNICODE_STRING localsystem;
            private LSA_UNICODE_STRING secretName;
    
            public LSAutil (string key) {
                if (key.Length == 0) throw new Exception ("Key length zero");
                
                objectAttributes = new LSA_OBJECT_ATTRIBUTES();
                objectAttributes.Length = 0;
                objectAttributes.RootDirectory = IntPtr.Zero;
                objectAttributes.Attributes = 0;
                objectAttributes.SecurityDescriptor = IntPtr.Zero;
                objectAttributes.SecurityQualityOfService = IntPtr.Zero;
    
                localsystem = new LSA_UNICODE_STRING();
                localsystem.Buffer = IntPtr.Zero;
                localsystem.Length = 0;
                localsystem.MaximumLength = 0;
    
                secretName = new LSA_UNICODE_STRING();
                secretName.Buffer = Marshal.StringToHGlobalUni(key);
                secretName.Length = (UInt16)(key.Length * UnicodeEncoding.CharSize);
                secretName.MaximumLength = (UInt16)((key.Length + 1) * UnicodeEncoding.CharSize);
            }
    
            private IntPtr GetLsaPolicy(LSA_AccessPolicy access) {
                IntPtr LsaPolicyHandle;
                uint ntsResult = LsaOpenPolicy(ref this.localsystem, ref this.objectAttributes, (uint)access, out LsaPolicyHandle);
                uint winErrorCode = LsaNtStatusToWinError(ntsResult);
                if (winErrorCode != 0) throw new Exception("LsaOpenPolicy failed: " + winErrorCode);
                return LsaPolicyHandle;
            }
    
            private static void ReleaseLsaPolicy(IntPtr LsaPolicyHandle) {
                uint ntsResult = LsaClose(LsaPolicyHandle);
                uint winErrorCode = LsaNtStatusToWinError(ntsResult);
                if (winErrorCode != 0) throw new Exception("LsaClose failed: " + winErrorCode);
            }
    
            public void SetSecret(string value) {
                LSA_UNICODE_STRING lusSecretData = new LSA_UNICODE_STRING();
    
                if (value.Length > 0) {
                    lusSecretData.Buffer = Marshal.StringToHGlobalUni(value);
                    lusSecretData.Length = (UInt16)(value.Length * UnicodeEncoding.CharSize);
                    lusSecretData.MaximumLength = (UInt16)((value.Length + 1) * UnicodeEncoding.CharSize);
                } else {
                    lusSecretData.Buffer = IntPtr.Zero;
                    lusSecretData.Length = 0;
                    lusSecretData.MaximumLength = 0;
                }
    
                IntPtr LsaPolicyHandle = GetLsaPolicy(LSA_AccessPolicy.POLICY_CREATE_SECRET);
                uint result = LsaStorePrivateData(LsaPolicyHandle, ref secretName, ref lusSecretData);
                ReleaseLsaPolicy(LsaPolicyHandle);
    
                uint winErrorCode = LsaNtStatusToWinError(result);
                if (winErrorCode != 0) throw new Exception("StorePrivateData failed: " + winErrorCode);
            }
        }
    }
"@

    # Configure registry for auto-logon, adding .\ prefix to ensure local account usage
    Write-Host "Setting up auto-logon registry entries..."
    Set-ItemProperty -Path $RegPath -Name "DefaultUserName" -Value ".\$user" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "1" -ErrorAction SilentlyContinue

    # Configure auto-logon count if specified
    if ($AutoLogonCount -ne "0") {
        Set-ItemProperty -Path $RegPath -Name "AutoLogonCount" -Value ([UInt32]::Parse($AutoLogonCount))
    } else {
        Remove-ItemProperty -Path $RegPath -Name "AutoLogonCount" -ErrorAction SilentlyContinue
    }

    # Store password securely in LSA
    Write-Host "Storing password in LSA..."
    [PInvoke.LSAUtil.LSAutil]::new("DefaultPassword").SetSecret($pass)

    # Verify the configuration
    Write-Host "Verifying configuration..."
    $settings = Get-ItemProperty -Path $RegPath
    if ($settings.DefaultUserName -eq ".\$user" -and 
        $settings.AutoAdminLogon -eq "1") {
        Write-Host "Auto-logon configured successfully!" -ForegroundColor Green
        Write-Host "Please restart your computer to apply the changes."
        return $true
    } else {
        Write-Host "Error: Auto-logon configuration failed!" -ForegroundColor Red
        return $false
    }
}

### UPDATE USER AND PASS HERE: ##
Set-Autologon -user "LibCirc" -pass "L1bC1rc!1234" -AutoLogonCount "0"