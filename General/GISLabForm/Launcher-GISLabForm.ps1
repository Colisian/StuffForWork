<# 
  Launcher-GISLabFormBlocker.ps1
  - Opens Survey123 in Edge kiosk mode
  - Displays a full-screen overlay window that blocks the desktop
  - Keeps relaunching Edge if closed, until the user attests they've submitted the form
#>

param(
  [string]$SurveyUrl = "https://survey123.arcgis.com/share/830e8534db9d4a39b81facf3fc72577d"
  
)

# ----- config / logging -----
$AppName   = "GISLab Check-In Blocker"
$BaseDir   = "C:\ProgramData\GISLab\FormBlocker"
$LogFile   = Join-Path $BaseDir "FormBlocker.log"

New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
Function Write-Log {
  param([string]$Msg)
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  "$ts`t$Msg" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}
Write-Log "===== $AppName starting for user [$env:USERNAME] ====="

# ----- single-instance guard per user -----
$mutexName = "Global\GISLabFormBlocker-$($env:USERNAME)"
$mutex = New-Object System.Threading.Mutex($false, $mutexName, [ref]$createdNew)
if (-not $createdNew) {
  Write-Log "Another instance is already running; exiting."
  return
}

# ----- resolve Edge path -----
$edgeExeDefault = "$Env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe"
$edgeExeAlt     = "$Env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
$EdgeExe = if (Test-Path $edgeExeDefault) { $edgeExeDefault } elseif (Test-Path $edgeExeAlt) { $edgeExeAlt } else { "msedge.exe" }

# ----- function to (re)launch kiosk Edge -----
Function Start-EdgeKiosk {
  try {
    $args = @(
      "--kiosk", $SurveyUrl,
      "--edge-kiosk-type=fullscreen",
      "--no-first-run",
      "--disable-features=Translate,msImplicitScroll"
    )
    Write-Log "Launching Edge kiosk: $EdgeExe $($args -join ' ')"
    Start-Process -FilePath $EdgeExe -ArgumentList $args | Out-Null
  } catch {
    Write-Log "Failed to start Edge in kiosk mode: $($_.Exception.Message)"
  }
}

# ----- detect Edge kiosk process (rough) -----
Function IsEdgeOpen {
  try {
    $procs = Get-Process -Name "msedge" -ErrorAction SilentlyContinue
    return [bool]$procs
  } catch { return $false }
}

# ----- WPF overlay (full-screen, always-on-top) -----
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# XAML for full-screen overlay
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="$AppName"
        WindowStyle="None"
        ResizeMode="NoResize"
        WindowState="Maximized"
        Topmost="True"
        ShowInTaskbar="False"
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
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" >
          <Button x:Name="OpenFormBtn" Content="Open/Bring Form" Padding="18,10" Margin="0,0,12,0" FontSize="14"/>
          <Button x:Name="ContinueBtn" Content="Continue" Padding="18,10" FontSize="14" IsEnabled="False"/>
        </StackPanel>
      </StackPanel>
    </Border>

    <StackPanel Grid.Row="1" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,18,0,0">
      <TextBlock Foreground="#FFFFFFFF" Opacity="0.8" Text="If the form window is closed, click 'Open/Bring Form'."
                 FontSize="12" />
    </StackPanel>
  </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader (New-Object System.Xml.XmlDocument))
$xmlDoc = New-Object System.Xml.XmlDocument
$xmlDoc.LoadXml($xaml)
$reader = New-Object System.Xml.XmlNodeReader($xmlDoc)
$window = [Windows.Markup.XamlReader]::Load($reader)

$OpenFormBtn = $window.FindName("OpenFormBtn")
$ContinueBtn = $window.FindName("ContinueBtn")
$AttestCheck = $window.FindName("AttestCheck")

# Enable Continue only if checkbox ticked
$AttestCheck.Add_Checked(  { $ContinueBtn.IsEnabled = $true  })
$AttestCheck.Add_Unchecked({ $ContinueBtn.IsEnabled = $false })

# Open/Bring form handler
$OpenFormBtn.Add_Click({
  if (-not (IsEdgeOpen)) {
    Start-EdgeKiosk
  } else {
    # Try to bring Edge to front (best-effort)
    try {
      (Get-Process msedge -ErrorAction SilentlyContinue | Select-Object -First 1).MainWindowHandle | Out-Null
    } catch {}
  }
})

# Continue button closes blocker
$ContinueBtn.Add_Click({
  Write-Log "User confirmed submission; closing blocker."
  $window.Close()
})

# Background timer that keeps Edge open
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(5)
$timer.Add_Tick({
  if (-not (IsEdgeOpen)) {
    Write-Log "Edge appears closed; relaunching kiosk."
    Start-EdgeKiosk
  }
})
$timer.Start()

# Initial kiosk launch
Start-EdgeKiosk

# Show overlay (blocks until closed)
[void]$window.ShowDialog()




Write-Log "===== $AppName finished for user [$env:USERNAME] ====="
