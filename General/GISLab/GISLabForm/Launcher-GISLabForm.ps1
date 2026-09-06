<#
.SYNOPSIS
    GIS Lab Check-In Helper - shows the Survey123 check-in form at user logon.

.DESCRIPTION
    Opens the check-in form in an Edge kiosk window alongside a small
    attestation dialog (bottom-right). If the user closes Edge before
    confirming completion, the form is relaunched. The dialog cannot be
    closed until the user confirms; there is no taskbar manipulation, so
    a crash or forced kill leaves the desktop untouched.

.NOTES
    Author:  GIS Lab
    Date:    2026-09-06
    Version: 2.1
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

# Log unexpected terminating errors from setup or the WPF dispatcher.
trap {
    Write-Log "FATAL: $($_.Exception.Message)"
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

$window        = [Windows.Markup.XamlReader]::Parse($xaml)
$OpenFormBtn   = $window.FindName('OpenFormBtn')
$CloseKioskBtn = $window.FindName('CloseKioskBtn')
$AttestCheck   = $window.FindName('AttestCheck')

$AttestCheck.Add_Checked(  { $CloseKioskBtn.IsEnabled = $true  })
$AttestCheck.Add_Unchecked({ $CloseKioskBtn.IsEnabled = $false })

$script:UserConfirmed = $false

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
    Write-Log 'User confirmed submission; stopping kiosk and closing dialog.'
    $script:UserConfirmed = $true
    try { $timer.Stop() } catch {}
    Stop-EdgeKiosk
    $window.Close()
})

# Keep the form open while the user hasn't confirmed
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(5)
$timer.Add_Tick({
    if (-not $script:UserConfirmed -and -not (IsEdgeOpen)) {
        Write-Log 'Kiosk Edge closed; relaunching.'
        Start-EdgeKiosk
        Start-Sleep -Milliseconds 500
        Set-EdgeForeground
    }
})

# ---------------- Run ----------------
try {
    Start-EdgeKiosk
    Start-Sleep -Milliseconds 800
    Set-EdgeForeground

    # Position the dialog bottom-right
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $window.Left = $wa.Right - $window.Width - 20
        $window.Top  = $wa.Bottom - $window.Height - 20
    } catch {}

    $timer.Start()
    [void]$window.ShowDialog()
}
finally {
    try { $timer.Stop() } catch {}
    Stop-EdgeKiosk
    try { $mutex.ReleaseMutex() } catch {}
    try { $mutex.Dispose() } catch {}
}

if ($LaunchArcGISProAfter -and (Test-Path $ArcGISProPath)) {
    Write-Log 'Launching ArcGIS Pro after check-in.'
    Start-Process -FilePath $ArcGISProPath
}

Write-Log "===== $AppName finished for user [$env:USERNAME] ====="
