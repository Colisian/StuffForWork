<#
.SYNOPSIS
Detects the completed deployment and the current local kiosk auto-logon state.
.NOTES
Author: UMD Libraries IT / Oji. Date: 2026-10-06. Version: 1.1.0.
Run in 64-bit context as SYSTEM. Intune needs exit 0 plus stdout for detection.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$requiredVersion = '2026.10.06.2'
$expectedUser = 'LibCirc'
try {
    if (-not [Environment]::Is64BitProcess) { exit 1 }
    $marker = Get-ItemProperty 'HKLM:\SOFTWARE\UMDLibraries\KioskAutoLogon'
    if ($marker.DeploymentVersion -ne $requiredVersion -or $marker.UserName -ne $expectedUser) { exit 1 }
    $startupSource = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\AxisTV Engage\Start AxisTV Engage Playback.lnk'
    $startupFolder = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonStartup)
    $startupShortcut = Join-Path $startupFolder 'UMD-AxisTV Engage Playback.lnk'
    if (-not (Test-Path -LiteralPath $startupSource -PathType Leaf) -or -not (Test-Path -LiteralPath $startupShortcut -PathType Leaf)) { exit 1 }
    $startupHash = (Get-FileHash -LiteralPath $startupShortcut -Algorithm SHA256).Hash
    if ($startupHash -ne (Get-FileHash -LiteralPath $startupSource -Algorithm SHA256).Hash -or $startupHash -ne $marker.StartupShortcutHash) { exit 1 }
    $path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $settings = Get-ItemProperty $path
    if ($settings.AutoAdminLogon -ne '1' -or $settings.DefaultUserName -ne ".\$expectedUser" -or $settings.DefaultDomainName -ne $env:COMPUTERNAME) { exit 1 }
    if ((Get-Item $path).GetValueNames() -contains 'DefaultPassword' -or (Get-Item $path).GetValueNames() -contains 'AutoLogonCount') { exit 1 }
    $localUser = Get-LocalUser -Name $expectedUser
    if (-not $localUser.Enabled -or $null -ne $localUser.PasswordExpires -or ($localUser.AccountExpires -and $localUser.AccountExpires -le (Get-Date))) { exit 1 }
    if (-not ('UMDLibraries.AutologonSecret' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace UMDLibraries {
    public static class AutologonSecret {
        [StructLayout(LayoutKind.Sequential)]
        private struct UnicodeString { public ushort Length, MaximumLength; public IntPtr Buffer; }
        [StructLayout(LayoutKind.Sequential)]
        private struct ObjectAttributes {
            public uint Length; public IntPtr RootDirectory; public UnicodeString ObjectName;
            public uint Attributes; public IntPtr SecurityDescriptor, SecurityQualityOfService;
        }
        [DllImport("advapi32.dll")] private static extern uint LsaOpenPolicy(IntPtr system, ref ObjectAttributes attributes, uint access, out IntPtr handle);
        [DllImport("advapi32.dll")] private static extern uint LsaStorePrivateData(IntPtr handle, ref UnicodeString key, IntPtr value);
        [DllImport("advapi32.dll")] private static extern uint LsaRetrievePrivateData(IntPtr handle, ref UnicodeString key, out IntPtr value);
        [DllImport("advapi32.dll")] private static extern uint LsaNtStatusToWinError(uint status);
        [DllImport("advapi32.dll")] private static extern uint LsaFreeMemory(IntPtr memory);
        [DllImport("advapi32.dll")] private static extern uint LsaClose(IntPtr handle);
        private static UnicodeString MakeString(string value) {
            return new UnicodeString { Length = checked((ushort)(value.Length * 2)), MaximumLength = checked((ushort)((value.Length + 1) * 2)), Buffer = Marshal.StringToHGlobalUni(value) };
        }
        private static void Check(uint status) { if (status != 0) throw new Win32Exception((int)LsaNtStatusToWinError(status)); }
        private static IntPtr Open(uint access) {
            ObjectAttributes attributes = new ObjectAttributes();
            attributes.Length = (uint)Marshal.SizeOf(typeof(ObjectAttributes));
            IntPtr handle; Check(LsaOpenPolicy(IntPtr.Zero, ref attributes, access, out handle)); return handle;
        }
        // Passing a null data pointer deletes the secret. Never return or log its contents.
        public static void Store(string password) {
            UnicodeString key = MakeString("DefaultPassword");
            UnicodeString value = new UnicodeString();
            IntPtr handle = IntPtr.Zero, data = IntPtr.Zero;
            try {
                handle = Open(0x20);
                if (password != null) {
                    value = MakeString(password); data = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(UnicodeString)));
                    Marshal.StructureToPtr(value, data, false);
                }
                Check(LsaStorePrivateData(handle, ref key, data));
            } finally {
                if (value.Buffer != IntPtr.Zero) {
                    for (int i = 0; i < value.MaximumLength; i++) Marshal.WriteByte(value.Buffer, i, 0);
                    Marshal.FreeHGlobal(value.Buffer);
                }
                if (data != IntPtr.Zero) Marshal.FreeHGlobal(data);
                Marshal.FreeHGlobal(key.Buffer); if (handle != IntPtr.Zero) LsaClose(handle);
            }
        }
        public static bool Exists() {
            UnicodeString key = MakeString("DefaultPassword"); IntPtr handle = IntPtr.Zero, data = IntPtr.Zero;
            try {
                handle = Open(0x4);
                uint status = LsaRetrievePrivateData(handle, ref key, out data);
                if (LsaNtStatusToWinError(status) == 2) return false;
                Check(status); return data != IntPtr.Zero && ((UnicodeString)Marshal.PtrToStructure(data, typeof(UnicodeString))).Length > 0;
            } finally {
                if (data != IntPtr.Zero) LsaFreeMemory(data);
                Marshal.FreeHGlobal(key.Buffer); if (handle != IntPtr.Zero) LsaClose(handle);
            }
        }
    }
}

"@
    }
    if (-not [UMDLibraries.AutologonSecret]::Exists()) { exit 1 }
    Write-Output "UMD kiosk auto-logon $requiredVersion detected"
    exit 0
} catch { exit 1 }

