<#
  Launcher-GISLab.ps1
  GIS Lab Check-In Helper (Edge kiosk + confirmation dialog, hides taskbar during session)
#>

param (
    [string] $SurveyUrl = "https://go.umd.edu/lib-GIS-lab",
    [switch] $LaunchArcGISProAfter,
    [string] $ArcGISProPath = "C:\Program Files\ArcGIS\Pro\bin\ArcGISPro.exe"
)

# ---------------- Ensure STA (WPF requires Single-Threaded Apartment) ----------------
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    # Build argument list and forward all bound parameters + any leftover args
    $argList = @('-NoProfile','-Sta','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    foreach ($key in $PSBoundParameters.Keys) {
        if ($key -eq 'LaunchArcGISProAfter') {
            if ($PSBoundParameters[$key]) { $argList += "-$key" }
        } else {
            $argList += @("-$key", $PSBoundParameters[$key])
        }
    }
    if ($args) { $argList += $args }
    & powershell.exe @argList
    exit $LASTEXITCODE
}

# ---------------- Logging ----------------
$AppName = "GIS Lab Check-In Blocker"
$BaseDir = "C:\ProgramData\GISLab\FormBlocker"
$LogFile = Join-Path $BaseDir "FormBlocker.log"
New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null

function Write-Log {
    param([string]$Msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts`t$Msg" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}
Write-Log "===== $AppName starting for user [$env:USERNAME] ====="

# ---------------- Single instance guard ----------------
$mutexName = "Global\GISLabFormBlocker-$($env:USERNAME)"
[bool]$createdNew = $false
$mutex = New-Object System.Threading.Mutex($false, $mutexName, [ref]$createdNew)
if (-not $createdNew) {
    Write-Log "Another instance already running; exiting."
    return
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
        $args = @(
            "--kiosk", $SurveyUrl,
            "--edge-kiosk-type=fullscreen",
            "--no-first-run",
            "--disable-features=Translate,msImplicitScroll"
        )
        Write-Log "Launching Edge kiosk: $EdgeExe $($args -join ' ')"
        $p = Start-Process -FilePath $EdgeExe -ArgumentList $args -PassThru
        if ($p -and $script:EdgePids -notcontains $p.Id) { $script:EdgePids += $p.Id }
    } catch {
        Write-Log "Failed to launch Edge kiosk: $($_.Exception.Message)"
    }
}

function Get-KioskEdgeProcs {
    $byPid = @()
    foreach ($pids in $script:EdgePids) {
        $proc = Get-Process -Id $pids -ErrorAction SilentlyContinue
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

function Bring-EdgeToFront {
    try {
        $p = Get-KioskEdgeProcs | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if ($p) {
            [Win32]::ShowWindow($p.MainWindowHandle, 5) | Out-Null  # SW_SHOW
            [Win32]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
        }
    } catch {}
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
        WindowStyle="ToolWindow"
        ResizeMode="NoResize"
        Width="420"
        Height="200"
        Topmost="True"
        ShowInTaskbar="False"
        WindowStartupLocation="Manual"
        Background="#FFFFFFFF">
  <Border CornerRadius="10" BorderBrush="#DDDDDD" BorderThickness="1" Padding="16" Background="#FFFFFFFF">
    <StackPanel>
      <TextBlock Text="GIS Lab Check-In" FontSize="18" FontWeight="Bold" Margin="0,0,0,6" />
      <TextBlock Text="Complete the form in Edge. When done, confirm below to close the kiosk." TextWrapping="Wrap" Margin="0,0,0,12"/>
      <CheckBox x:Name="AttestCheck" Content="I attest I completed the form." Margin="0,0,0,12"/>
      <StackPanel Orientation="Horizontal">
        <Button x:Name="OpenFormBtn" Content="Open/Bring Form" Padding="12,6" Margin="0,0,8,0" />
        <Button x:Name="CloseKioskBtn" Content="I've completed (Close Kiosk)" Padding="12,6" IsEnabled="False" />
      </StackPanel>
    </StackPanel>
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
    Bring-EdgeToFront
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
        Bring-EdgeToFront
    }
})
$timer.Start()

# ---------------- Run (hide taskbar, show dialog, restore taskbar) ----------------
try {
    Hide-Taskbar

    Start-EdgeKiosk
    Start-Sleep -Milliseconds 800
    Bring-EdgeToFront

    # Position the window bottom-right
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $window.Left = $wa.Right - $window.Width - 20
        $window.Top  = $wa.Bottom - $window.Height - 20
    } catch {}

    # If dialog gets activated, ensure Edge stays in front (just in case)
    $window.Add_Activated({ Bring-EdgeToFront })

    [void]$window.ShowDialog()
}
finally {
    Show-Taskbar
}

if ($LaunchArcGISProAfter -and (Test-Path $ArcGISProPath)) {
    Write-Log "Launching ArcGIS Pro after check-in."
    Start-Process -FilePath $ArcGISProPath
}

Write-Log "===== $AppName finished for user [$env:USERNAME] ====="