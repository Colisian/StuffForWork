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
