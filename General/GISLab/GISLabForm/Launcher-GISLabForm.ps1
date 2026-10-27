<#
.SYNOPSIS
    GIS Lab Check-In Helper - shows the Survey123 check-in form at user logon.

.DESCRIPTION
    Opens the check-in form in an Edge kiosk window alongside a small
    attestation dialog (bottom-right). If the user closes Edge before
    confirming completion, the form is relaunched. The dialog cannot be
    closed until the user confirms.

    Until the user confirms, the session is locked down across every display:
      - Every monitor that is not showing the form is covered by a topmost,
        non-activating shield window (so extended displays are unusable).
      - The primary and secondary taskbars are hidden and re-hidden every second.
      - A low-level keyboard filter (on its own thread) swallows the Windows
        keys, Alt+Tab, Alt+Esc, Alt+F4, Ctrl+Esc and Ctrl+Shift+Esc.
    Everything is restored when the user confirms, on any handled error, and
    at logoff. Ctrl+Alt+Del cannot be filtered by design (secure attention).

.NOTES
    Author:  GIS Lab
    Date:    2026-10-27
    Version: 2.2
#>
[CmdletBinding()]
param (
    [string] $SurveyUrl = 'https://go.umd.edu/lib-GIS-lab',
    [switch] $LaunchArcGISProAfter,
    [string] $ArcGISProPath = 'C:\Program Files\ArcGIS\Pro\bin\ArcGISPro.exe',
    [int]    $StartupDelay = 3              # Seconds to wait for desktop readiness
)

$ErrorActionPreference = 'Stop'

# ---------------- Ensure STA (WPF requires Single-Threaded Apartment) ----------------
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $argList = @('-NoProfile', '-Sta', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
    foreach ($key in $PSBoundParameters.Keys) {
        $val = $PSBoundParameters[$key]
        if ($val -is [switch]) {
            if ($val) { $argList += "-$key" }
        } else {
            $argList += @("-$key", $val)
        }
    }
    & powershell.exe @argList
    exit $LASTEXITCODE
}

# ---------------- Logging ----------------
# The installer grants users write access only to this runtime-log directory.
# A session-specific name prevents concurrent sessions from sharing a file.
$AppName = 'GIS Lab Check-In'
$BaseDir = 'C:\ProgramData\UMDLibraries\GISLabForm'
$LogDir = Join-Path $BaseDir 'Logs'
$script:SessionId = (Get-Process -Id $PID).SessionId
$safeUserName = $env:USERNAME -replace '[^a-zA-Z0-9._-]', '_'
$LogFile = Join-Path $LogDir "FormBlocker-$safeUserName-$($script:SessionId).log"

function Write-Log {
    param([string]$Msg)
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        "$ts`t$Msg" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    } catch {}
}
Write-Log "===== $AppName starting for user [$env:USERNAME] ====="

# Log unexpected terminating errors from setup or the WPF dispatcher, and never
# leave the user without a taskbar or keyboard shortcuts.
trap {
    Write-Log "FATAL: $($_.Exception.Message)"
    try { Stop-Lockdown } catch {}
    try { $mutex.ReleaseMutex() } catch {}
    try { $mutex.Dispose() } catch {}
    exit 1
}

# ---------------- Single-instance guard ----------------
# Local\ namespace scopes the mutex to this logon session, so two different
# users on the same machine (fast user switching) don't block each other.
[bool]$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\GISLabCheckIn', [ref]$createdNew)
if (-not $createdNew) {
    $owned = $false
    try {
        $owned = $mutex.WaitOne(3000, $false)
    } catch [System.Threading.AbandonedMutexException] {
        # Previous owner died without releasing; ownership transfers to us
        $owned = $true
    }
    if (-not $owned) {
        Write-Log 'Another instance is already running in this session. Exiting.'
        exit 0
    }
}

# ---------------- Startup delay for desktop readiness ----------------
if ($StartupDelay -gt 0) {
    Write-Log "Waiting $StartupDelay seconds for desktop readiness..."
    Start-Sleep -Seconds $StartupDelay
}

# ---------------- Win32 interop (bring Edge to foreground) ----------------
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
$SW_SHOW = 5

# ---------------- Win32 interop (multi-display lockdown) ----------------
# The keyboard filter runs on a dedicated thread with its own message loop so a
# busy WPF/PowerShell thread can never hit LowLevelHooksTimeout (which would
# let keys through or get the hook silently removed). Nothing is recorded.
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

public static class GisLockdown {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

  [StructLayout(LayoutKind.Sequential)]
  struct POINT { public int X; public int Y; }

  [StructLayout(LayoutKind.Sequential)]
  struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }

  [StructLayout(LayoutKind.Sequential)]
  struct KBDLLHOOKSTRUCT { public uint vkCode; public uint scanCode; public uint flags; public uint time; public IntPtr dwExtraInfo; }

  [StructLayout(LayoutKind.Sequential)]
  struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public POINT pt; }

  delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
  delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdc, ref RECT rect, IntPtr data);
  delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc fn, IntPtr hMod, uint threadId);
  [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hhk);
  [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
  [DllImport("user32.dll")] static extern int GetMessage(out MSG msg, IntPtr hWnd, uint min, uint max);
  [DllImport("user32.dll")] static extern bool PostThreadMessage(uint threadId, uint msg, IntPtr wParam, IntPtr lParam);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int cmd);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int index);
  [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hWnd, int index, int value);
  [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc fn, IntPtr lParam);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc fn, IntPtr data);
  [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO info);
  [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);
  [DllImport("user32.dll")] static extern IntPtr MonitorFromPoint(POINT pt, uint flags);

  static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
  const uint SWP_NOSIZE = 0x0001, SWP_NOMOVE = 0x0002, SWP_NOACTIVATE = 0x0010;
  const int GWL_EXSTYLE = -20, WS_EX_TOOLWINDOW = 0x00000080, WS_EX_NOACTIVATE = 0x08000000;

  // ---- Keyboard filter ----
  static readonly LowLevelKeyboardProc HookProc = KeyboardCallback;
  static Thread hookThread;
  static uint hookThreadId;
  static IntPtr hookHandle = IntPtr.Zero;

  public static bool StartKeyboardFilter() {
    if (hookThread != null) return hookHandle != IntPtr.Zero;
    ManualResetEvent ready = new ManualResetEvent(false);
    hookThread = new Thread(() => {
      hookThreadId = GetCurrentThreadId();
      hookHandle = SetWindowsHookEx(13, HookProc, GetModuleHandle(null), 0); // WH_KEYBOARD_LL
      ready.Set();
      if (hookHandle == IntPtr.Zero) return;
      MSG msg;
      while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0) { }
      UnhookWindowsHookEx(hookHandle);
      hookHandle = IntPtr.Zero;
    });
    hookThread.IsBackground = true;
    hookThread.Start();
    ready.WaitOne(5000);
    return hookHandle != IntPtr.Zero;
  }

  public static void StopKeyboardFilter() {
    if (hookThread == null) return;
    PostThreadMessage(hookThreadId, 0x0012, IntPtr.Zero, IntPtr.Zero); // WM_QUIT
    hookThread.Join(2000);
    hookThread = null;
  }

  static IntPtr KeyboardCallback(int nCode, IntPtr wParam, IntPtr lParam) {
    if (nCode >= 0) {
      KBDLLHOOKSTRUCT k = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
      if (IsBlockedKey(k)) return (IntPtr)1;
    }
    return CallNextHookEx(hookHandle, nCode, wParam, lParam);
  }

  static bool IsBlockedKey(KBDLLHOOKSTRUCT k) {
    uint vk = k.vkCode;
    bool alt = (k.flags & 0x20) != 0;                                   // LLKHF_ALTDOWN
    bool ctrl = (GetAsyncKeyState(0x11) & 0x8000) != 0;
    if (vk == 0x5B || vk == 0x5C) return true;                          // Windows keys (Start, Win+ shortcuts)
    if (alt && (vk == 0x09 || vk == 0x1B || vk == 0x73)) return true;   // Alt+Tab, Alt+Esc, Alt+F4
    if (ctrl && vk == 0x1B) return true;                                // Ctrl+Esc, Ctrl+Shift+Esc
    return false;
  }

  // ---- Taskbars ----
  public static void SetTaskbarsVisible(bool visible) {
    List<IntPtr> bars = new List<IntPtr>();
    IntPtr primary = FindWindow("Shell_TrayWnd", null);
    if (primary != IntPtr.Zero) bars.Add(primary);
    IntPtr secondary = IntPtr.Zero;
    while ((secondary = FindWindowEx(IntPtr.Zero, secondary, "Shell_SecondaryTrayWnd", null)) != IntPtr.Zero) {
      bars.Add(secondary);
    }
    foreach (IntPtr bar in bars) {
      if (IsWindowVisible(bar) != visible) ShowWindow(bar, visible ? 5 : 0); // SW_SHOW / SW_HIDE
    }
  }

  // ---- Displays ----
  public static RECT[] GetMonitorRects() {
    List<RECT> rects = new List<RECT>();
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero,
      delegate(IntPtr h, IntPtr dc, ref RECT r, IntPtr d) { rects.Add(r); return true; }, IntPtr.Zero);
    return rects.ToArray();
  }

  public static RECT GetPrimaryMonitorRect() {
    return GetMonitorRect(MonitorFromPoint(new POINT(), 1)); // MONITOR_DEFAULTTOPRIMARY
  }

  public static RECT GetWindowMonitorRect(IntPtr hWnd) {
    return GetMonitorRect(MonitorFromWindow(hWnd, 2)); // MONITOR_DEFAULTTONEAREST
  }

  static RECT GetMonitorRect(IntPtr monitor) {
    MONITORINFO info = new MONITORINFO();
    info.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
    GetMonitorInfo(monitor, ref info);
    return info.rcMonitor;
  }

  // ---- Windows ----
  // Largest visible, unowned top-level window belonging to any of the given PIDs.
  public static IntPtr FindLargestWindow(int[] pids) {
    if (pids == null || pids.Length == 0) return IntPtr.Zero;
    HashSet<uint> wanted = new HashSet<uint>();
    foreach (int p in pids) wanted.Add((uint)p);
    IntPtr best = IntPtr.Zero;
    long bestArea = 0;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h) || GetWindow(h, 4) != IntPtr.Zero) return true; // GW_OWNER
      uint pid;
      GetWindowThreadProcessId(h, out pid);
      if (!wanted.Contains(pid)) return true;
      RECT r;
      GetWindowRect(h, out r);
      long area = (long)(r.Right - r.Left) * (r.Bottom - r.Top);
      if (area > bestArea) { bestArea = area; best = h; }
      return true;
    }, IntPtr.Zero);
    return best;
  }

  public static void MakeNonActivating(IntPtr hWnd) {
    int ex = GetWindowLong(hWnd, GWL_EXSTYLE);
    SetWindowLong(hWnd, GWL_EXSTYLE, ex | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);
  }

  public static void CoverRect(IntPtr hWnd, RECT r) {
    SetWindowPos(hWnd, HWND_TOPMOST, r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top, SWP_NOACTIVATE);
  }

  public static void RaiseTopmost(IntPtr hWnd) {
    SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }

  public static void MoveToBottomRight(IntPtr hWnd, RECT area, int margin) {
    RECT w;
    GetWindowRect(hWnd, out w);
    int x = area.Right - (w.Right - w.Left) - margin;
    int y = area.Bottom - (w.Bottom - w.Top) - margin;
    SetWindowPos(hWnd, HWND_TOPMOST, x, y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
  }
}
"@

# ---------------- Edge path resolution ----------------
$edgeCandidates = @(
    "${Env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$Env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
)
$EdgeExe = $edgeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $EdgeExe) { $EdgeExe = 'msedge.exe' }  # resolves via App Paths
$edgeProfileDir = Join-Path $env:LOCALAPPDATA 'UMDLibraries\GISLabForm\EdgeProfile'
New-Item -ItemType Directory -Path $edgeProfileDir -Force | Out-Null

# Track PIDs we launch; scope any fallback matching to this logon session so we
# never touch kiosk Edge windows belonging to other sessions.
$script:EdgePids  = @()
# Refreshed by the 5-second watchdog so the 1-second lockdown tick avoids CIM queries.
$script:KioskPids = @()

function Start-EdgeKiosk {
    try {
        $edgeArgs = @(
            '--kiosk', $SurveyUrl,
            '--edge-kiosk-type=fullscreen',
            '--no-first-run',
            "`"--user-data-dir=$edgeProfileDir`"",
            '--disable-features=Translate,msImplicitScroll'
        )
        Write-Log "Launching Edge kiosk: $EdgeExe $($edgeArgs -join ' ')"
        $p = Start-Process -FilePath $EdgeExe -ArgumentList $edgeArgs -PassThru
        if ($p -and $script:EdgePids -notcontains $p.Id) { $script:EdgePids += $p.Id }
    } catch {
        Write-Log "Failed to launch Edge kiosk: $($_.Exception.Message)"
    }
}

function Get-KioskEdgeProcs {
    $matched = @()
    foreach ($trackedPid in $script:EdgePids) {
        $proc = Get-Process -Id $trackedPid -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -eq 'msedge' -and $proc.SessionId -eq $script:SessionId) {
            $matched += $proc
        }
    }

    # Edge hands off to an existing browser process, so the tracked PID can die
    # while the kiosk window lives on. Always merge exact command-line matches.
    try {
        $urlPattern = [regex]::Escape($SurveyUrl)
        $profilePattern = [regex]::Escape("--user-data-dir=$edgeProfileDir")
        $cims = Get-CimInstance Win32_Process -Filter "Name='msedge.exe' AND SessionId=$($script:SessionId)" |
                Where-Object {
                    $_.CommandLine -match '(?i)(?:^|\s)--kiosk(?:\s|=)' -and
                    ($_.CommandLine -match $urlPattern -or $_.CommandLine -match $profilePattern)
                }
        if ($cims) {
            $matched += @($cims | ForEach-Object {
                Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
            })
        }
    } catch {}
    return @($matched | Where-Object { $_ } | Sort-Object Id -Unique)
}

function IsEdgeOpen { return (Get-KioskEdgeProcs).Count -gt 0 }

function Set-EdgeForeground {
    try {
        $p = Get-KioskEdgeProcs | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if ($p) {
            [Win32]::ShowWindow($p.MainWindowHandle, $SW_SHOW) | Out-Null
            [Win32]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
        }
    } catch {
        Write-Log "Set-EdgeForeground error: $($_.Exception.Message)"
    }
}

function Stop-EdgeKiosk {
    try {
        Write-Log 'Stopping kiosk Edge.'
        $procs = Get-KioskEdgeProcs
        foreach ($p in $procs) { [void]$p.CloseMainWindow() }
        Start-Sleep -Milliseconds 800
        $procs = Get-KioskEdgeProcs
        if ($procs) { $procs | Stop-Process -Force -ErrorAction SilentlyContinue }
    } catch {
        Write-Log "Failed stopping Edge kiosk: $($_.Exception.Message)"
    }
}

# ---------------- WPF dialog (small, bottom-right) ----------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$AppName"
        WindowStyle="None"
        ResizeMode="NoResize"
        Width="380"
        Height="220"
        Topmost="True"
        ShowInTaskbar="False"
        AllowsTransparency="True"
        Background="Transparent"
        WindowStartupLocation="Manual">
  <Border CornerRadius="12" BorderBrush="#E21833" BorderThickness="2" Background="White">
    <Border.Effect>
      <DropShadowEffect BlurRadius="15" ShadowDepth="2" Opacity="0.3"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <!-- Header -->
      <Border Grid.Row="0" Background="#E21833" CornerRadius="10,10,0,0" Padding="16,12">
        <TextBlock Text="GIS Lab Check-In" FontSize="16" FontWeight="SemiBold" Foreground="White"/>
      </Border>

      <!-- Content -->
      <StackPanel Grid.Row="1" Margin="16">
        <TextBlock Text="Please complete the check-in form in the browser window."
                   TextWrapping="Wrap" Margin="0,0,0,12" FontSize="12" Foreground="#333333"/>

        <CheckBox x:Name="AttestCheck" Margin="0,0,0,16">
          <TextBlock Text="I confirm I have completed the form" FontSize="12"/>
        </CheckBox>

        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>

          <Button x:Name="OpenFormBtn" Grid.Column="0" Content="Show Form"
                  Padding="12,8" Margin="0,0,6,0" Background="#F5F5F5"
                  BorderBrush="#CCCCCC" FontSize="11"/>
          <Button x:Name="CloseKioskBtn" Grid.Column="1" Content="Done"
                  Padding="12,8" Margin="6,0,0,0" Background="#E21833"
                  Foreground="White" BorderBrush="#E21833" FontSize="11"
                  IsEnabled="False"/>
        </Grid>
      </StackPanel>
    </Grid>
  </Border>
</Window>
"@

# Full-screen cover for every display that is not showing the form. Size and
# position are applied in physical pixels by GisLockdown.CoverRect.
$shieldXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="$AppName"
        WindowStyle="None"
        ResizeMode="NoResize"
        Topmost="True"
        ShowInTaskbar="False"
        ShowActivated="False"
        Background="#1B1F24"
        WindowStartupLocation="Manual">
  <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center" MaxWidth="700">
    <Border Background="#E21833" Height="6" Width="120" Margin="0,0,0,24"/>
    <TextBlock Text="GIS Lab Check-In" FontSize="36" FontWeight="SemiBold" Foreground="White"
               HorizontalAlignment="Center" Margin="0,0,0,16"/>
    <TextBlock Text="Complete the check-in form and confirm it in the GIS Lab Check-In box to unlock this computer."
               FontSize="20" Foreground="#D0D4D9" TextWrapping="Wrap" TextAlignment="Center"/>
  </StackPanel>
</Window>
"@

$window        = [Windows.Markup.XamlReader]::Parse($xaml)
$OpenFormBtn   = $window.FindName('OpenFormBtn')
$CloseKioskBtn = $window.FindName('CloseKioskBtn')
$AttestCheck   = $window.FindName('AttestCheck')

$AttestCheck.Add_Checked(  { $CloseKioskBtn.IsEnabled = $true  })
$AttestCheck.Add_Unchecked({ $CloseKioskBtn.IsEnabled = $false })

$script:UserConfirmed = $false

# ---------------- Multi-display lockdown ----------------
$script:Shields = @()
$script:MonitorSignature = $null
$script:DialogMonitorKey = $null
$script:DialogHwnd = [IntPtr]::Zero
$script:LastLockdownError = $null
$script:LockdownActive = $false

function Get-RectKey {
    param($Rect)
    return '{0},{1},{2},{3}' -f $Rect.Left, $Rect.Top, $Rect.Right, $Rect.Bottom
}

function New-Shield {
    param($Rect)
    $shield = [Windows.Markup.XamlReader]::Parse($shieldXaml)
    $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($shield)).EnsureHandle()
    [GisLockdown]::MakeNonActivating($hwnd)
    [GisLockdown]::CoverRect($hwnd, $Rect)
    return [pscustomobject]@{ Window = $shield; Hwnd = $hwnd; Rect = $Rect; Key = (Get-RectKey $Rect) }
}

function Close-Shields {
    foreach ($shield in @($script:Shields)) {
        try { $shield.Window.Close() } catch {}
    }
    $script:Shields = @()
}

function Start-Lockdown {
    $script:LockdownActive = $true
    try {
        if ([GisLockdown]::StartKeyboardFilter()) {
            Write-Log 'Keyboard filter active (Win, Alt+Tab, Alt+Esc, Alt+F4, Ctrl+Esc, Ctrl+Shift+Esc).'
        } else {
            Write-Log 'WARNING: Keyboard filter could not be installed; continuing with display/taskbar lockdown only.'
        }
    } catch {
        Write-Log "WARNING: Keyboard filter error: $($_.Exception.Message)"
    }
    Update-Lockdown
}

# Called every second: re-hide taskbars, cover every display except the one
# showing the form, and keep the check-in dialog above everything on that display.
function Update-Lockdown {
    if ($script:UserConfirmed -or -not $script:LockdownActive) { return }
    try {
        [GisLockdown]::SetTaskbarsVisible($false)

        $monitors = @([GisLockdown]::GetMonitorRects())
        $signature = ($monitors | ForEach-Object { Get-RectKey $_ }) -join ';'
        if ($signature -ne $script:MonitorSignature) {
            Write-Log "Display layout detected ($($monitors.Count)): $signature"
            Close-Shields
            $script:Shields = @($monitors | ForEach-Object { New-Shield $_ })
            $script:MonitorSignature = $signature
            $script:DialogMonitorKey = $null
        }

        $edgeHwnd = [GisLockdown]::FindLargestWindow([int[]]@($script:EdgePids + $script:KioskPids))
        $formKey = $null
        $dialogRect = [GisLockdown]::GetPrimaryMonitorRect()
        if ($edgeHwnd -ne [IntPtr]::Zero) {
            $dialogRect = [GisLockdown]::GetWindowMonitorRect($edgeHwnd)
            $formKey = Get-RectKey $dialogRect
        }

        # If the form is not on screen (relaunching), every display stays covered.
        foreach ($shield in $script:Shields) {
            if ($shield.Key -eq $formKey) {
                if ($shield.Window.IsVisible) { $shield.Window.Hide() }
            } else {
                if (-not $shield.Window.IsVisible) { $shield.Window.Show() }
                [GisLockdown]::CoverRect($shield.Hwnd, $shield.Rect)
            }
        }

        # Only reposition when the form moves to another display, so a user can
        # still drag the dialog out of the way.
        $dialogKey = Get-RectKey $dialogRect
        if ($dialogKey -ne $script:DialogMonitorKey) {
            [GisLockdown]::MoveToBottomRight($script:DialogHwnd, $dialogRect, 20)
            $script:DialogMonitorKey = $dialogKey
        }
        [GisLockdown]::RaiseTopmost($script:DialogHwnd)
        $script:LastLockdownError = $null
    } catch {
        if ($_.Exception.Message -ne $script:LastLockdownError) {
            $script:LastLockdownError = $_.Exception.Message
            Write-Log "Lockdown update error: $($script:LastLockdownError)"
        }
    }
}

# Idempotent; safe to call from the Done button, finally, and trap.
function Stop-Lockdown {
    $script:LockdownActive = $false
    try { $lockTimer.Stop() } catch {}
    try { [GisLockdown]::StopKeyboardFilter() } catch {}
    try { [GisLockdown]::SetTaskbarsVisible($true) } catch {}
    Close-Shields
}

# WindowStyle=None has no title bar; allow dragging the dialog out of the way
$window.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} })

# Block Alt+F4 / programmatic close until the user confirms (logoff still force-closes)
$window.Add_Closing({
    param($s, $e)
    if (-not $script:UserConfirmed) { $e.Cancel = $true }
})

$OpenFormBtn.Add_Click({
    if (-not (IsEdgeOpen)) { Start-EdgeKiosk; Start-Sleep -Milliseconds 500 }
    Set-EdgeForeground
})

$CloseKioskBtn.Add_Click({
    Write-Log 'User confirmed submission; releasing lockdown, stopping kiosk and closing dialog.'
    $script:UserConfirmed = $true
    try { $timer.Stop() } catch {}
    Stop-Lockdown
    Stop-EdgeKiosk
    $window.Close()
})

# Keep the form open while the user hasn't confirmed
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(5)
$timer.Add_Tick({
    if ($script:UserConfirmed) { return }
    $procs = Get-KioskEdgeProcs
    $script:KioskPids = @($procs | ForEach-Object { $_.Id })
    if ($procs.Count -eq 0) {
        Write-Log 'Kiosk Edge closed; relaunching.'
        Start-EdgeKiosk
        Start-Sleep -Milliseconds 500
        Set-EdgeForeground
    }
})

# Re-assert shields, hidden taskbars and dialog z-order
$lockTimer = New-Object System.Windows.Threading.DispatcherTimer
$lockTimer.Interval = [TimeSpan]::FromSeconds(1)
$lockTimer.Add_Tick({ Update-Lockdown })

# Lockdown starts once the dialog is on screen so it can be placed above the shields
$window.Add_ContentRendered({
    Start-Lockdown
    $lockTimer.Start()
})

# ---------------- Run ----------------
try {
    Start-EdgeKiosk
    Start-Sleep -Milliseconds 800
    Set-EdgeForeground

    # Initial position (primary work area); Update-Lockdown moves the dialog to
    # whichever display the form opened on.
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $window.Left = $wa.Right - $window.Width - 20
        $window.Top  = $wa.Bottom - $window.Height - 20
    } catch {}
    $script:DialogHwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).EnsureHandle()

    $timer.Start()
    [void]$window.ShowDialog()
}
finally {
    try { $timer.Stop() } catch {}
    Stop-Lockdown
    Stop-EdgeKiosk
    try { $mutex.ReleaseMutex() } catch {}
    try { $mutex.Dispose() } catch {}
}

if ($LaunchArcGISProAfter -and (Test-Path $ArcGISProPath)) {
    Write-Log 'Launching ArcGIS Pro after check-in.'
    Start-Process -FilePath $ArcGISProPath
}

Write-Log "===== $AppName finished for user [$env:USERNAME] ====="
