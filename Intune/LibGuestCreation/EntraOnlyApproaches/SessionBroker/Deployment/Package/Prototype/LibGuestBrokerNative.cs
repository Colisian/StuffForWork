// LibGuestBrokerNative.cs
//
// Native launch surface for the LibGuest session broker.
//
// Author:  Oji / UMD Libraries
// Date:    2026-07-26
// Version: 0.2.0
//
// Wraps CreateProcessWithLogonW so the broker can authenticate a SIMS-issued
// libguestN@UMD.EDU credential and run an allowlisted application under the
// mapped local security context.
//
// Password handling contract:
//   The plaintext password exists only inside an unmanaged buffer allocated by
//   Marshal.SecureStringToCoTaskMemUnicode and released by
//   Marshal.ZeroFreeCoTaskMemUnicode in a finally block that runs immediately
//   after the API call returns. It is never copied into a managed System.String,
//   never placed on a command line, and never logged.
//
// Launch sequence:
//   1. CreateProcessWithLogonW with CREATE_SUSPENDED. Nothing executes as the
//      guest until step 4, so the token can be inspected without a race and an
//      identity-only test never runs guest code at all.
//   2. Assign the process to a job object carrying
//      JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, so every descendant dies when the
//      broker closes the job handle or the broker process itself exits.
//   3. Read the process token to confirm which identity Windows actually
//      produced (proves the Kerberos UserList mapping resolved as expected).
//   4. Resume the thread, or terminate the job for an identity-only test.
//
// IMPORTANT: C# 5 only. Windows PowerShell 5.1 compiles Add-Type sources with
// the in-box .NET Framework CodeDOM provider. No string interpolation, no
// expression-bodied members, no out-variable declarations, no nameof.
//
// Single-session assumption: the broker supervises one guest session at a time,
// so the job and process handles are held in static fields. StartSession throws
// if a session is already active.

using System;
using System.Runtime.InteropServices;
using System.Security;
using System.Security.Principal;
using System.Text;

namespace UMD.Libraries.LibGuest
{
    /// <summary>
    /// Outcome of a guest launch attempt. Contains no credential material.
    /// </summary>
    public sealed class BrokerLaunchResult
    {
        public bool Succeeded;

        /// <summary>Win32 error from the failing call, or 0 on success.</summary>
        public int Win32Error;

        /// <summary>Which step failed, for the log. Empty on success.</summary>
        public string FailureStage;

        public int ProcessId;

        /// <summary>SID of the identity the launched process actually runs as.</summary>
        public string TokenSid;

        /// <summary>Resolved account name for TokenSid, e.g. MACHINE\libguest7.</summary>
        public string TokenAccount;

        public BrokerLaunchResult()
        {
            this.FailureStage = string.Empty;
            this.TokenSid = string.Empty;
            this.TokenAccount = string.Empty;
        }
    }

    public static class BrokerLauncher
    {
        private const uint LOGON_WITH_PROFILE = 0x00000001;
        private const uint CREATE_SUSPENDED = 0x00000004;
        private const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
        private const uint TOKEN_QUERY = 0x00000008;
        private const int JobObjectExtendedLimitInformation = 9;
        private const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
        private const uint WAIT_OBJECT_0 = 0x00000000;
        private const uint WAIT_TIMEOUT = 0x00000102;
        private const uint STILL_ACTIVE = 259;

        private static IntPtr jobHandle = IntPtr.Zero;
        private static IntPtr processHandle = IntPtr.Zero;
        private static IntPtr threadHandle = IntPtr.Zero;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct STARTUPINFO
        {
            public int cb;
            [MarshalAs(UnmanagedType.LPWStr)] public string lpReserved;
            [MarshalAs(UnmanagedType.LPWStr)] public string lpDesktop;
            [MarshalAs(UnmanagedType.LPWStr)] public string lpTitle;
            public int dwX;
            public int dwY;
            public int dwXSize;
            public int dwYSize;
            public int dwXCountChars;
            public int dwYCountChars;
            public int dwFillAttribute;
            public int dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public int dwProcessId;
            public int dwThreadId;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IO_COUNTERS
        {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateProcessWithLogonW(
            [MarshalAs(UnmanagedType.LPWStr)] string userName,
            [MarshalAs(UnmanagedType.LPWStr)] string domain,
            IntPtr password,
            uint logonFlags,
            [MarshalAs(UnmanagedType.LPWStr)] string applicationName,
            // StringBuilder, not string: the Unicode form of this API is
            // documented as able to modify lpCommandLine in place, and the
            // marshaller hands a managed string's own pinned buffer to native
            // code for LPWStr. Passing a string here risks mutating an interned
            // literal.
            StringBuilder commandLine,
            uint creationFlags,
            IntPtr environment,
            [MarshalAs(UnmanagedType.LPWStr)] string currentDirectory,
            ref STARTUPINFO startupInfo,
            out PROCESS_INFORMATION processInformation);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool OpenProcessToken(IntPtr processHandle, uint desiredAccess, out IntPtr tokenHandle);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObjectW(IntPtr jobAttributes, [MarshalAs(UnmanagedType.LPWStr)] string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint infoLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateJobObject(IntPtr job, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateProcess(IntPtr process, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint ResumeThread(IntPtr thread);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        /// <summary>
        /// True while a guest session's job object is still held open.
        /// </summary>
        public static bool SessionIsActive
        {
            get { return jobHandle != IntPtr.Zero; }
        }

        /// <summary>
        /// Authenticates the supplied principal and starts an allowlisted
        /// application under the resulting security context.
        /// </summary>
        /// <param name="userPrincipalName">UPN form, e.g. libguest7@UMD.EDU.</param>
        /// <param name="logonDomain">
        /// Null in production: the UPN carries the realm, and CreateProcessWithLogonW
        /// requires a null domain when lpUsername is a UPN. Exists so the native
        /// path can be exercised against a plain local account (domain = machine
        /// name, username = bare SAM name) on an ordinary Windows box, without
        /// needing a Shared PC device or a live SIMS credential.
        /// </param>
        /// <param name="password">Caller retains ownership; this method does not dispose it.</param>
        /// <param name="applicationPath">Absolute path, validated by the caller against the allowlist.</param>
        /// <param name="arguments">Fixed arguments from configuration. Never patron-supplied.</param>
        /// <param name="workingDirectory">Directory readable by the guest account.</param>
        /// <param name="resumeAfterLaunch">
        /// False leaves the process suspended so the caller can read the token
        /// without any guest code executing. Used by the identity test.
        /// </param>
        /// <param name="superviseSession">
        /// True puts the process in a job object with KILL_ON_JOB_CLOSE, so the
        /// broker can enforce a time limit and guarantee cleanup — but the guest's
        /// application dies when the broker exits.
        ///
        /// False skips the job entirely and releases our handles once the process
        /// is running, so the application outlives the broker. That is the
        /// launch-and-exit model: the broker is purely an authentication gate and
        /// stops existing afterwards. It trades away the session timer and
        /// deterministic cleanup.
        /// </param>
        public static BrokerLaunchResult StartSession(
            string userPrincipalName,
            string logonDomain,
            SecureString password,
            string applicationPath,
            string arguments,
            string workingDirectory,
            bool resumeAfterLaunch,
            bool superviseSession)
        {
            if (SessionIsActive)
            {
                throw new InvalidOperationException("A guest session is already active. Call EndSession first.");
            }
            if (string.IsNullOrEmpty(userPrincipalName))
            {
                throw new ArgumentNullException("userPrincipalName");
            }
            if (password == null)
            {
                throw new ArgumentNullException("password");
            }
            if (string.IsNullOrEmpty(applicationPath))
            {
                throw new ArgumentNullException("applicationPath");
            }

            BrokerLaunchResult result = new BrokerLaunchResult();

            // CreateProcessWithLogonW expects argv[0] in the command line even
            // when lpApplicationName is supplied. Extra capacity because the API
            // may write into this buffer.
            string commandLineText = "\"" + applicationPath + "\"";
            if (!string.IsNullOrEmpty(arguments))
            {
                commandLineText = commandLineText + " " + arguments;
            }
            StringBuilder commandLine = new StringBuilder(commandLineText, commandLineText.Length + 1);

            STARTUPINFO startupInfo = new STARTUPINFO();
            startupInfo.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            // lpDesktop stays null so the process appears on the broker's
            // desktop. That mixed-identity desktop is the documented ceiling of
            // this approach, not an oversight.

            PROCESS_INFORMATION processInformation = new PROCESS_INFORMATION();
            IntPtr passwordBuffer = IntPtr.Zero;
            bool created = false;
            int lastError = 0;

            try
            {
                passwordBuffer = Marshal.SecureStringToCoTaskMemUnicode(password);

                created = CreateProcessWithLogonW(
                    userPrincipalName,
                    // Null in production: the UPN carries the realm. Non-null
                    // only when testing against a local SAM account.
                    string.IsNullOrEmpty(logonDomain) ? null : logonDomain,
                    passwordBuffer,
                    LOGON_WITH_PROFILE,
                    applicationPath,
                    commandLine,
                    CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT,
                    IntPtr.Zero,
                    workingDirectory,
                    ref startupInfo,
                    out processInformation);

                // Must be read before anything else can overwrite it.
                lastError = Marshal.GetLastWin32Error();
            }
            finally
            {
                if (passwordBuffer != IntPtr.Zero)
                {
                    Marshal.ZeroFreeCoTaskMemUnicode(passwordBuffer);
                    passwordBuffer = IntPtr.Zero;
                }
            }

            if (!created)
            {
                result.Succeeded = false;
                result.Win32Error = lastError;
                result.FailureStage = "CreateProcessWithLogonW";
                return result;
            }

            processHandle = processInformation.hProcess;
            threadHandle = processInformation.hThread;
            result.ProcessId = processInformation.dwProcessId;

            try
            {
                // Job object first: it must own the process before any guest
                // code runs, otherwise a child could escape supervision.
                if (superviseSession && !CreateJobForCurrentProcess())
                {
                    result.Succeeded = false;
                    result.Win32Error = Marshal.GetLastWin32Error();
                    result.FailureStage = "AssignProcessToJobObject";
                    EndSession();
                    return result;
                }

                ReadTokenIdentity(result);

                if (resumeAfterLaunch)
                {
                    if (ResumeThread(threadHandle) == unchecked((uint)-1))
                    {
                        result.Succeeded = false;
                        result.Win32Error = Marshal.GetLastWin32Error();
                        result.FailureStage = "ResumeThread";
                        EndSession();
                        return result;
                    }

                    if (!superviseSession)
                    {
                        // Launch and exit: let go of the process without killing
                        // it. After this, SessionIsActive is false and EndSession
                        // is a no-op, so the broker shutting down cannot take the
                        // guest's application with it.
                        ReleaseHandles();
                    }
                }
                else
                {
                    // Identity test: the credential authenticated and the token
                    // mapped, which is the whole question. Tear down without
                    // ever letting the process execute an instruction.
                    EndSession();
                }

                result.Succeeded = true;
                return result;
            }
            catch
            {
                EndSession();
                throw;
            }
        }

        /// <summary>
        /// Creates the job object and assigns the launched process to it.
        /// KILL_ON_JOB_CLOSE guarantees cleanup even if the broker crashes.
        /// </summary>
        private static bool CreateJobForCurrentProcess()
        {
            jobHandle = CreateJobObjectW(IntPtr.Zero, null);
            if (jobHandle == IntPtr.Zero)
            {
                return false;
            }

            JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

            int limitsSize = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
            IntPtr limitsBuffer = Marshal.AllocHGlobal(limitsSize);
            try
            {
                Marshal.StructureToPtr(limits, limitsBuffer, false);
                if (!SetInformationJobObject(jobHandle, JobObjectExtendedLimitInformation, limitsBuffer, (uint)limitsSize))
                {
                    return false;
                }
            }
            finally
            {
                Marshal.FreeHGlobal(limitsBuffer);
            }

            return AssignProcessToJobObject(jobHandle, processHandle);
        }

        /// <summary>
        /// Records the identity the launched process actually runs as. A failure
        /// here is not fatal to the launch: it only costs the log detail that
        /// proves the Kerberos UserList mapping resolved correctly.
        /// </summary>
        private static void ReadTokenIdentity(BrokerLaunchResult result)
        {
            IntPtr tokenHandle = IntPtr.Zero;
            try
            {
                if (!OpenProcessToken(processHandle, TOKEN_QUERY, out tokenHandle))
                {
                    return;
                }

                using (WindowsIdentity identity = new WindowsIdentity(tokenHandle))
                {
                    if (identity.User != null)
                    {
                        result.TokenSid = identity.User.Value;
                    }
                    result.TokenAccount = identity.Name;
                }
            }
            catch
            {
                // Diagnostic only; leave the fields empty.
            }
            finally
            {
                if (tokenHandle != IntPtr.Zero)
                {
                    CloseHandle(tokenHandle);
                }
            }
        }

        /// <summary>
        /// Polls the launched process. Returns true once it has exited.
        /// Pass 0 to poll without blocking, which is what the UI timer does so
        /// the dispatcher keeps pumping.
        /// </summary>
        public static bool WaitForSessionExit(uint milliseconds)
        {
            if (processHandle == IntPtr.Zero)
            {
                return true;
            }
            return WaitForSingleObject(processHandle, milliseconds) == WAIT_OBJECT_0;
        }

        /// <summary>
        /// Closes our handles without terminating anything, so the launched
        /// process keeps running after the broker goes away. Only valid when no
        /// job object was created: closing a job carrying KILL_ON_JOB_CLOSE would
        /// terminate the tree, which is the opposite of the intent here.
        /// </summary>
        private static void ReleaseHandles()
        {
            if (threadHandle != IntPtr.Zero)
            {
                CloseHandle(threadHandle);
                threadHandle = IntPtr.Zero;
            }
            if (processHandle != IntPtr.Zero)
            {
                CloseHandle(processHandle);
                processHandle = IntPtr.Zero;
            }
        }

        /// <summary>
        /// Terminates every process in the job and releases all handles.
        /// Safe to call repeatedly and safe to call when no session is active.
        /// </summary>
        public static void EndSession()
        {
            if (jobHandle != IntPtr.Zero)
            {
                TerminateJobObject(jobHandle, 0);
                CloseHandle(jobHandle);
                jobHandle = IntPtr.Zero;
            }
            if (processHandle != IntPtr.Zero)
            {
                // Covers the window where the process exists but job assignment
                // failed: without this, closing the handles would orphan a
                // suspended process running as the guest. Redundant but harmless
                // once the job has already terminated the tree, and a no-op for
                // a process that has already exited.
                TerminateProcess(processHandle, 0);
            }
            if (threadHandle != IntPtr.Zero)
            {
                CloseHandle(threadHandle);
                threadHandle = IntPtr.Zero;
            }
            if (processHandle != IntPtr.Zero)
            {
                CloseHandle(processHandle);
                processHandle = IntPtr.Zero;
            }
        }
    }
}
