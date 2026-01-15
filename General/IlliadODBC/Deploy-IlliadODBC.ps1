# Save as: Deploy-IlliadODBC.ps1
# Deploys ILLiad ODBC configuration as User DSN
# GUI Version - runs with hidden PowerShell window
#
# SECURITY WARNING: This script stores the database password in plain text
# in the Windows registry at HKCU:\SOFTWARE\ODBC\ODBC.INI\[DSN Name]\PWD
# This is an inherent limitation of ODBC User DSNs with SQL authentication.
# Any process running under your user account can read this password.
# Ensure your workstation uses full disk encryption and strong authentication.

# Load WPF assemblies for modern UI
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Configuration
$dsnName = "ILLiadLink"
$serverName = "10.126.5.89"
$database = "ILLData"
$loginID = "ILLiadLink"

# Function to show modern WPF password input dialog
function Get-PasswordDialog {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ILLiad ODBC Setup"
        Height="250" Width="450"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#F3F3F3"
        WindowStyle="SingleBorderWindow">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#0078D4"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="20,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="4"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#106EBE"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#005A9E"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="#E1E1E1"/>
            <Setter Property="Foreground" Value="#1A1A1A"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="20,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="4"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#CCCCCC"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#B3B3B3"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0"
                   Text="ILLiad ODBC Database Connection Setup"
                   FontSize="16"
                   FontWeight="SemiBold"
                   Foreground="#1A1A1A"
                   FontFamily="Segoe UI"/>

        <TextBlock Grid.Row="1"
                   Text="Enter the ILLiadLink database password:"
                   FontSize="13"
                   Foreground="#444444"
                   FontFamily="Segoe UI"
                   Margin="0,16,0,8"/>

        <PasswordBox x:Name="PasswordBox"
                     Grid.Row="2"
                     Height="36"
                     FontSize="14"
                     FontFamily="Segoe UI"
                     Padding="10,8"
                     BorderBrush="#CCCCCC"
                     BorderThickness="1">
            <PasswordBox.Resources>
                <Style TargetType="Border">
                    <Setter Property="CornerRadius" Value="4"/>
                </Style>
            </PasswordBox.Resources>
        </PasswordBox>

        <StackPanel Grid.Row="4"
                    Orientation="Horizontal"
                    HorizontalAlignment="Right"
                    Margin="0,16,0,0">
            <Button x:Name="CancelButton"
                    Content="Cancel"
                    Style="{StaticResource SecondaryButton}"
                    Margin="0,0,12,0"
                    MinWidth="80"/>
            <Button x:Name="OKButton"
                    Content="OK"
                    MinWidth="80"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    $passwordBox = $window.FindName("PasswordBox")
    $okButton = $window.FindName("OKButton")
    $cancelButton = $window.FindName("CancelButton")

    $script:dialogResult = $null

    $okButton.Add_Click({
        $script:dialogResult = $passwordBox.Password
        $window.Close()
    })

    $cancelButton.Add_Click({
        $script:dialogResult = $null
        $window.Close()
    })

    $window.Add_ContentRendered({
        $passwordBox.Focus()
    })

    # Handle Enter key
    $window.Add_KeyDown({
        if ($_.Key -eq "Return") {
            $script:dialogResult = $passwordBox.Password
            $window.Close()
        }
        elseif ($_.Key -eq "Escape") {
            $script:dialogResult = $null
            $window.Close()
        }
    })

    $window.ShowDialog() | Out-Null

    return $script:dialogResult
}

# Function to show modern WPF message dialog
function Show-MessageDialog {
    param(
        [string]$Message,
        [string]$Title,
        [string]$Type = "Info"  # Info, Error, Warning
    )

    $iconColor = switch ($Type) {
        "Error"   { "#D32F2F" }
        "Warning" { "#F9A825" }
        default   { "#0078D4" }
    }

    $iconPath = switch ($Type) {
        "Error"   { "M12,2C17.53,2 22,6.47 22,12C22,17.53 17.53,22 12,22C6.47,22 2,17.53 2,12C2,6.47 6.47,2 12,2M15.59,7L12,10.59L8.41,7L7,8.41L10.59,12L7,15.59L8.41,17L12,13.41L15.59,17L17,15.59L13.41,12L17,8.41L15.59,7Z" }
        "Warning" { "M13,14H11V10H13M13,18H11V16H13M1,21H23L12,2L1,21Z" }
        default   { "M12,2A10,10 0 0,1 22,12A10,10 0 0,1 12,22A10,10 0 0,1 2,12A10,10 0 0,1 12,2M12,17L17,12L12,7V10H8V14H12V17Z" }
    }

    # Escape special characters for XAML
    $escapedMessage = [System.Security.SecurityElement]::Escape($Message)
    $escapedTitle = [System.Security.SecurityElement]::Escape($Title)

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$escapedTitle"
        SizeToContent="Height"
        Width="420"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#F3F3F3"
        WindowStyle="SingleBorderWindow">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#0078D4"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="24,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="4"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#106EBE"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#005A9E"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Viewbox Grid.Row="0" Width="48" Height="48" HorizontalAlignment="Left" Margin="0,0,0,16">
            <Canvas Width="24" Height="24">
                <Path Data="$iconPath" Fill="$iconColor"/>
            </Canvas>
        </Viewbox>

        <TextBlock Grid.Row="1"
                   Text="$escapedMessage"
                   FontSize="13"
                   Foreground="#1A1A1A"
                   FontFamily="Segoe UI"
                   TextWrapping="Wrap"
                   Margin="0,0,0,24"/>

        <Button x:Name="OKButton"
                Grid.Row="2"
                Content="OK"
                HorizontalAlignment="Right"
                MinWidth="88"/>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    $okButton = $window.FindName("OKButton")

    $okButton.Add_Click({
        $window.Close()
    })

    $window.Add_KeyDown({
        if ($_.Key -eq "Return" -or $_.Key -eq "Escape") {
            $window.Close()
        }
    })

    $window.ShowDialog() | Out-Null
}

# Function to show Yes/No confirmation dialog
function Show-ConfirmDialog {
    param(
        [string]$Message,
        [string]$Title
    )

    $escapedMessage = [System.Security.SecurityElement]::Escape($Message)
    $escapedTitle = [System.Security.SecurityElement]::Escape($Title)

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$escapedTitle"
        SizeToContent="Height"
        Width="420"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#F3F3F3"
        WindowStyle="SingleBorderWindow">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#0078D4"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="20,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="4"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#106EBE"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#005A9E"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="#E1E1E1"/>
            <Setter Property="Foreground" Value="#1A1A1A"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="20,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="4"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#CCCCCC"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#B3B3B3"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Viewbox Grid.Row="0" Width="48" Height="48" HorizontalAlignment="Left" Margin="0,0,0,16">
            <Canvas Width="24" Height="24">
                <Path Data="M13,14H11V10H13M13,18H11V16H13M1,21H23L12,2L1,21Z" Fill="#F9A825"/>
            </Canvas>
        </Viewbox>

        <TextBlock Grid.Row="1"
                   Text="$escapedMessage"
                   FontSize="13"
                   Foreground="#1A1A1A"
                   FontFamily="Segoe UI"
                   TextWrapping="Wrap"
                   Margin="0,0,0,24"/>

        <StackPanel Grid.Row="2"
                    Orientation="Horizontal"
                    HorizontalAlignment="Right">
            <Button x:Name="NoButton"
                    Content="No"
                    Style="{StaticResource SecondaryButton}"
                    Margin="0,0,12,0"
                    MinWidth="80"/>
            <Button x:Name="YesButton"
                    Content="Yes"
                    MinWidth="80"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    $yesButton = $window.FindName("YesButton")
    $noButton = $window.FindName("NoButton")

    $script:confirmResult = $false

    $yesButton.Add_Click({
        $script:confirmResult = $true
        $window.Close()
    })

    $noButton.Add_Click({
        $script:confirmResult = $false
        $window.Close()
    })

    $window.Add_KeyDown({
        if ($_.Key -eq "Escape") {
            $script:confirmResult = $false
            $window.Close()
        }
    })

    $window.ShowDialog() | Out-Null

    return $script:confirmResult
}

# Get password from user via GUI dialog
$plainPassword = Get-PasswordDialog

if ([string]::IsNullOrWhiteSpace($plainPassword)) {
    Show-MessageDialog -Message "Password is required to configure the ODBC connection." -Title "ILLiad ODBC Setup - Error" -Type "Error"
    exit 1
}

# Detect Office architecture with robust detection
$officeArch = $null
$registryPaths = @(
    "HKLM:\Software\Microsoft\Office\ClickToRun\Configuration",
    "HKLM:\Software\Wow6432Node\Microsoft\Office\ClickToRun\Configuration"
)

foreach ($regPath in $registryPaths) {
    try {
        $config = Get-ItemProperty $regPath -ErrorAction Stop
        if ($config.Platform) {
            $officeArch = $config.Platform
            break
        }
    } catch {
        # Path not found, continue to next
    }
}

if (-not $officeArch) {
    $continueSetup = Show-ConfirmDialog -Message "Could not detect Office installation.`n`nDefaulting to 32-bit Office configuration.`n`nContinue with 32-bit setup?" -Title "ILLiad ODBC Setup - Warning"
    if (-not $continueSetup) {
        exit 1
    }
    $officeArch = "x86"
}

$platform = if ($officeArch -eq "x64") { "64-bit" } else { "32-bit" }
$driverPath = if ($platform -eq "64-bit") { "C:\Windows\System32\sqlncli11.dll" } else { "C:\Windows\SysWOW64\sqlncli11.dll" }

# Verify SQL Server Native Client driver exists
if (-not (Test-Path $driverPath)) {
    $errorMessage = "SQL Server Native Client 11.0 driver not found.

Detected Office: $platform
Expected location: $driverPath

To install SQL Server Native Client 11.0:
1. Download from Microsoft:
   https://www.microsoft.com/en-us/download/details.aspx?id=50402
2. Install the version matching your Office architecture
3. Run this setup again"

    Show-MessageDialog -Message $errorMessage -Title "ILLiad ODBC Setup - Missing Driver" -Type "Error"
    exit 1
}

# Remove old DSN configurations
Remove-OdbcDsn -Name $dsnName -DsnType User -Platform $platform -ErrorAction SilentlyContinue

# Create registry paths for User DSN
$regPath = "HKCU:\SOFTWARE\ODBC\ODBC.INI\$dsnName"
$regListPath = "HKCU:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources"

try {
    # Only create parent paths if they don't exist (avoid wiping existing DSNs)
    if (-not (Test-Path "HKCU:\SOFTWARE\ODBC\ODBC.INI")) {
        $null = New-Item -Path "HKCU:\SOFTWARE\ODBC\ODBC.INI" -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path $regListPath)) {
        $null = New-Item -Path $regListPath -Force -ErrorAction SilentlyContinue
    }
    # Remove and recreate the specific DSN key
    if (Test-Path $regPath) {
        Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -Path $regPath -Force -ErrorAction Stop
} catch {
    $errorMessage = "Failed to create registry entries for ODBC configuration.

Error: $($_.Exception.Message)

This may indicate a permissions issue or registry corruption."

    Show-MessageDialog -Message $errorMessage -Title "ILLiad ODBC Setup - Registry Error" -Type "Error"
    exit 1
}

# Configure ODBC DSN settings
$settings = @{
    "Driver" = $driverPath
    "Server" = $serverName
    "Database" = $database
    "UID" = $loginID
    "PWD" = $plainPassword
    "Trusted_Connection" = "No"
    "Encrypt" = "No"
    "TrustServerCertificate" = "Yes"
    "ApplicationIntent" = "READONLY"
    "LoginTimeout" = "60"
    "QueryTimeout" = "0"
}

try {
    foreach ($key in $settings.Keys) {
        Set-ItemProperty -Path $regPath -Name $key -Value $settings[$key] -Force -ErrorAction Stop
    }

    Set-ItemProperty -Path $regListPath -Name $dsnName -Value "SQL Server Native Client 11.0" -Force -ErrorAction Stop

} catch {
    $errorMessage = "Failed to configure ODBC settings in the registry.

Error: $($_.Exception.Message)

The configuration could not be completed."

    Show-MessageDialog -Message $errorMessage -Title "ILLiad ODBC Setup - Configuration Error" -Type "Error"

    # Clean up password before exit
    $plainPassword = $null
    [System.GC]::Collect()

    exit 1
}

$plainPassword = $null
[System.GC]::Collect()

# Show success message
$successMessage = "ILLiad ODBC connection configured successfully!

DSN Name: $dsnName
Database: $database

You can now use this connection in Microsoft Access."

Show-MessageDialog -Message $successMessage -Title "ILLiad ODBC Setup - Complete" -Type "Info"

exit 0
