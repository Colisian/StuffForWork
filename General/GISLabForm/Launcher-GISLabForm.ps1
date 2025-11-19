<#
  Launcher-GISLab.ps1
  GIS Lab Check-In Helper (Edge kiosk + confirmation dialog, hides taskbar during session)
#>

param (
    [string] $SurveyUrl = "https://go.umd.edu/lib-GIS-lab",
    [switch] $LaunchArcGISProAfter,
    [string] $ArcGISProPath = "C:\Program Files\ArcGIS\Pro\bin\ArcGISPro.exe",
    [int] $StartupDelay = 3,              # Seconds to wait for desktop readiness
    [switch] $SkipTaskbarHide             # Don't hide the taskbar
)

# ---------------- Ensure STA (WPF requires Single-Threaded Apartment) ----------------
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    # Build argument list and forward all bound parameters + any leftover args
    $argList = @('-NoProfile','-Sta','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    foreach ($key in $PSBoundParameters.Keys) {
        $val = $PSBoundParameters[$key]
        if ($val -is [switch]) {
            if ($val) { $argList += "-$key" }
        } else {
            $argList += @("-$key", $val)
        }
    }
    if ($args) { $argList += $args }
    $result = & powershell.exe @argList
    exit $LASTEXITCODE
}

# ---------------- Logging ----------------
$AppName = "GIS Lab Check-In"
$BaseDir = "C:\ProgramData\GISLab\FormBlocker"
$LogFile = Join-Path $BaseDir "FormBlocker.log"
New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null

function Write-Log {
    param([string]$Msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts`t$Msg" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}
Write-Log "===== $AppName starting for user [$env:USERNAME] ====="

# ---------------- Startup delay for desktop readiness ----------------
if ($StartupDelay -gt 0) {
    Write-Log "Waiting $StartupDelay seconds for desktop readiness..."
    Start-Sleep -Seconds $StartupDelay
}

# ---------------- Single instance guard with timeout ----------------
$mutexName = "Global\GISLabFormBlocker-$($env:USERNAME)"
[bool]$createdNew = $false
$mutex = $null

try {
    $mutex = New-Object System.Threading.Mutex($false, $mutexName, [ref]$createdNew)

    if (-not $createdNew) {
        # Try to acquire with timeout (5 seconds) in case previous instance crashed
        Write-Log "Mutex exists, waiting up to 5 seconds for release..."
        $acquired = $mutex.WaitOne(5000, $false)
        if (-not $acquired) {
            Write-Log "Could not acquire mutex after timeout; another instance may be running. Exiting."
            return
        }
        Write-Log "Acquired mutex after wait - previous instance likely crashed."
    }
} catch {
    Write-Log "Mutex error: $($_.Exception.Message) - proceeding anyway"
}

# ---------------- Win32 interop (foreground + taskbar control) ----------------
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
}
"@

$SW_HIDE = 0
$SW_SHOW = 5

function Hide-Taskbar {
  try {
    foreach ($cls in @('Shell_TrayWnd','Shell_SecondaryTrayWnd')) {
      $h = [Win32]::FindWindow($cls, $null)
      if ($h -ne [IntPtr]::Zero) { [Win32]::ShowWindow($h, $SW_HIDE) | Out-Null }
    }
    Write-Log "Taskbar hidden."
  } catch { Write-Log "Hide-Taskbar error: $($_.Exception.Message)" }
}
function Show-Taskbar {
  try {
    foreach ($cls in @('Shell_TrayWnd','Shell_SecondaryTrayWnd')) {
      $h = [Win32]::FindWindow($cls, $null)
      if ($h -ne [IntPtr]::Zero) { [Win32]::ShowWindow($h, $SW_SHOW) | Out-Null }
    }
    Write-Log "Taskbar restored."
  } catch { Write-Log "Show-Taskbar error: $($_.Exception.Message)" }
}

# ---------------- Edge path resolution ----------------
$edgeExeDefault = "$Env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe"
$edgeExeAlt     = "$Env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
$EdgeExe = if (Test-Path $edgeExeDefault) { $edgeExeDefault } elseif (Test-Path $edgeExeAlt) { $edgeExeAlt } else { "msedge.exe" }

# Track PIDs we launch so we only close kiosk instances we created
$script:EdgePids = @()

function Start-EdgeKiosk {
    try {
        $edgeArgs = @(
            "--kiosk", $SurveyUrl,
            "--edge-kiosk-type=fullscreen",
            "--no-first-run",
            "--disable-features=Translate,msImplicitScroll"
        )
        Write-Log "Launching Edge kiosk: $EdgeExe $($edgeArgs -join ' ')"
        $p = Start-Process -FilePath $EdgeExe -ArgumentList $edgeArgs -PassThru
        if ($p -and $script:EdgePids -notcontains $p.Id) { $script:EdgePids += $p.Id }
    } catch {
        Write-Log "Failed to launch Edge kiosk: $($_.Exception.Message)"
    }
}

function Get-KioskEdgeProcs {
    $byPid = @()
    foreach ($pidItem in $script:EdgePids) {
        $proc = Get-Process -Id $pidItem -ErrorAction SilentlyContinue
        if ($proc) { $byPid += $proc }
    }
    if ($byPid.Count -gt 0) { return $byPid }
    try {
        $cims = Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
                Where-Object { $_.CommandLine -match '\s--kiosk(\s|$)' }
        if ($cims) {
            return $cims | ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
        }
    } catch {}
    return @()
}

function IsEdgeOpen { return (Get-KioskEdgeProcs).Count -gt 0 }

function Set-EdgeForeground {
    try {
        $p = Get-KioskEdgeProcs | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if ($p) {
            [Win32]::ShowWindow($p.MainWindowHandle, 5) | Out-Null  # SW_SHOW
            [Win32]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
        }
    } catch {
        Write-Log "Set-EdgeForeground error: $($_.Exception.Message)"
    }
}

function Stop-EdgeKiosk {
    try {
        Write-Log "Stopping kiosk Edge."
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
$OpenFormBtn   = $window.FindName("OpenFormBtn")
$CloseKioskBtn = $window.FindName("CloseKioskBtn")
$AttestCheck   = $window.FindName("AttestCheck")

$AttestCheck.Add_Checked(  { $CloseKioskBtn.IsEnabled = $true  })
$AttestCheck.Add_Unchecked({ $CloseKioskBtn.IsEnabled = $false })

$script:UserConfirmed = $false

$OpenFormBtn.Add_Click({
    if (-not (IsEdgeOpen)) { Start-EdgeKiosk; Start-Sleep -Milliseconds 500 }
    Set-EdgeForeground
})

$CloseKioskBtn.Add_Click({
    Write-Log "User confirmed submission; stopping kiosk and closing dialog."
    $script:UserConfirmed = $true
    try { $timer.Stop() } catch {}
    Stop-EdgeKiosk
    $window.Close()
})

# Keep Edge alive while user hasn't confirmed
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(5)
$timer.Add_Tick({
    if (-not $script:UserConfirmed -and -not (IsEdgeOpen)) {
        Write-Log "Kiosk Edge closed; relaunching."
        Start-EdgeKiosk
        Start-Sleep -Milliseconds 500
        Set-EdgeForeground
    }
})
$timer.Start()

# ---------------- Run (hide taskbar, show dialog, restore taskbar) ----------------
try {
    if (-not $SkipTaskbarHide) {
        Hide-Taskbar
    }

    Start-EdgeKiosk
    Start-Sleep -Milliseconds 800
    Set-EdgeForeground

    # Position the window bottom-right
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $window.Left = $wa.Right - $window.Width - 20
        $window.Top  = $wa.Bottom - $window.Height - 20
    } catch {}

    # If dialog gets activated, ensure Edge stays in front (just in case)
    $window.Add_Activated({ Set-EdgeForeground })

    [void]$window.ShowDialog()
}
finally {
    if (-not $SkipTaskbarHide) {
        Show-Taskbar
    }
    # Release mutex
    if ($mutex) {
        try { $mutex.ReleaseMutex() } catch {}
        try { $mutex.Dispose() } catch {}
    }
}

if ($LaunchArcGISProAfter -and (Test-Path $ArcGISProPath)) {
    Write-Log "Launching ArcGIS Pro after check-in."
    Start-Process -FilePath $ArcGISProPath
}

Write-Log "===== $AppName finished for user [$env:USERNAME] ====="