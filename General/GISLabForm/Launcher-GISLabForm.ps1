<# 
Launcher-Form.ps1
GIS Lab Check-In Blocker
#>

param(
  [string]$SurveyUrl = "https://survey123.arcgis.com/share/830e8534db9d4a39b81facf3fc72577d",
  [switch]$LaunchArcGISProAfter = $false,
  [string]$ArcGISProPath = "C:\Program Files\ArcGIS\Pro\bin\ArcGISPro.exe"
)

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

# ---------------- Edge path ----------------
$edgeExeDefault = "$Env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe"
$edgeExeAlt     = "$Env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
$EdgeExe = if (Test-Path $edgeExeDefault) { $edgeExeDefault } elseif (Test-Path $edgeExeAlt) { $edgeExeAlt } else { "msedge.exe" }

function Start-EdgeKiosk {
  try {
    $args = @(
      "--kiosk", $SurveyUrl,
      "--edge-kiosk-type=fullscreen",
      "--no-first-run",
      "--disable-features=Translate,msImplicitScroll"
    )
    Write-Log "Launching Edge kiosk: $EdgeExe"
    Start-Process -FilePath $EdgeExe -ArgumentList $args | Out-Null
  } catch {
    Write-Log "Failed to launch Edge: $($_.Exception.Message)"
  }
}

function IsEdgeOpen {
  try {
    $procs = Get-Process -Name "msedge" -ErrorAction SilentlyContinue
    return [bool]$procs
  } catch { return $false }
}

# ---------------- Win32 interop (bring Edge forward) ----------------
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

function Bring-EdgeToFront {
  try {
    $p = Get-Process msedge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($p) {
      [Win32]::ShowWindow($p.MainWindowHandle, 5) | Out-Null # SW_SHOW
      [Win32]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
    }
  } catch {}
}

# ---------------- WPF overlay ----------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$AppName"
        WindowStyle="None"
        ResizeMode="NoResize"
        WindowState="Maximized"
        ShowInTaskbar="True"
        Background="#CC000000">
  <Grid Margin="40">
    <Grid.RowDefinitions>
      <RowDefinition Height="*" />
      <RowDefinition Height="Auto" />
    </Grid.RowDefinitions>

    <Border CornerRadius="16" Background="#FFFFFFFF" Padding="32" Grid.Row="0">
      <StackPanel>
        <TextBlock Text="GIS Lab Check-In Required" FontSize="32" FontWeight="Bold" Margin="0,0,0,16" />
        <TextBlock Text="Please complete the check-in form that opened in your browser. You will not be able to use the desktop until you confirm submission." 
                   FontSize="16" TextWrapping="Wrap" Margin="0,0,0,24" />
        <CheckBox x:Name="AttestCheck" Content="I attest that I have submitted the form." FontSize="16" Margin="0,0,0,24"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
          <Button x:Name="OpenFormBtn" Content="Open/Bring Form" Padding="18,10" Margin="0,0,12,0" FontSize="14"/>
          <Button x:Name="ContinueBtn" Content="Continue" Padding="18,10" FontSize="14" IsEnabled="False"/>
        </StackPanel>
      </StackPanel>
    </Border>

    <StackPanel Grid.Row="1" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,18,0,0">
      <TextBlock Foreground="#FFFFFFFF" Opacity="0.8" Text="If the form window is closed, click 'Open/Bring Form'." FontSize="12" />
    </StackPanel>
  </Grid>
</Window>
"@

$window = [Windows.Markup.XamlReader]::Parse($xaml)

$OpenFormBtn = $window.FindName("OpenFormBtn")
$ContinueBtn = $window.FindName("ContinueBtn")
$AttestCheck = $window.FindName("AttestCheck")

$AttestCheck.Add_Checked(  { $ContinueBtn.IsEnabled = $true  })
$AttestCheck.Add_Unchecked({ $ContinueBtn.IsEnabled = $false })

$OpenFormBtn.Add_Click({
  if (-not (IsEdgeOpen)) { Start-EdgeKiosk; Start-Sleep -Milliseconds 500 }
  Bring-EdgeToFront
})

$ContinueBtn.Add_Click({
  Write-Log "User confirmed submission; closing blocker."
  $window.Close()
})

# ---------------- Timer watchdog ----------------
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(5)
$timer.Add_Tick({
  if (-not (IsEdgeOpen)) { 
    Write-Log "Edge closed; relaunching kiosk."
    Start-EdgeKiosk
    Start-Sleep -Milliseconds 500
    Bring-EdgeToFront
  }
})
$timer.Start()

# ---------------- Run ----------------
Start-EdgeKiosk
Start-Sleep -Milliseconds 800
Bring-EdgeToFront

[void]$window.ShowDialog()

if ($LaunchArcGISProAfter -and (Test-Path $ArcGISProPath)) {
  Write-Log "Launching ArcGIS Pro after check-in."
  Start-Process -FilePath $ArcGISProPath
}

Write-Log "===== $AppName finished for user [$env:USERNAME] ====="