# Save as: Deploy-IlliadODBC.ps1
# Deploys ILLiad ODBC configuration as User DSN
# GUI Version - runs with hidden PowerShell window
#
# SECURITY WARNING: This script stores the database password in plain text
# in the Windows registry at HKCU:\SOFTWARE\ODBC\ODBC.INI\[DSN Name]\PWD
# This is an inherent limitation of ODBC User DSNs with SQL authentication.
# Any process running under your user account can read this password.
# Ensure your workstation uses full disk encryption and strong authentication.

# Load Windows Forms for GUI dialogs
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Configuration
$dsnName = "ILLiadLink"
$serverName = "10.126.5.89"
$database = "ILLData"
$loginID = "ILLiadLink"

# Function to show password input dialog
function Get-PasswordDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "ILLiad ODBC Setup"
    $form.Size = New-Object System.Drawing.Size(400, 200)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true

    # Title label
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Location = New-Object System.Drawing.Point(20, 20)
    $titleLabel.Size = New-Object System.Drawing.Size(360, 25)
    $titleLabel.Text = "ILLiad ODBC Database Connection Setup"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($titleLabel)

    # Instruction label
    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(20, 55)
    $label.Size = New-Object System.Drawing.Size(360, 20)
    $label.Text = "Enter the ILLiadLink database password:"
    $form.Controls.Add($label)

    # Password text box
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(20, 80)
    $textBox.Size = New-Object System.Drawing.Size(340, 20)
    $textBox.UseSystemPasswordChar = $true
    $form.Controls.Add($textBox)

    # OK button
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(200, 120)
    $okButton.Size = New-Object System.Drawing.Size(75, 25)
    $okButton.Text = "OK"
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $okButton
    $form.Controls.Add($okButton)

    # Cancel button
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(285, 120)
    $cancelButton.Size = New-Object System.Drawing.Size(75, 25)
    $cancelButton.Text = "Cancel"
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $cancelButton
    $form.Controls.Add($cancelButton)

    $form.Add_Shown({ $textBox.Select() })
    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $textBox.Text
    }
    return $null
}

# Get password from user via GUI dialog
$plainPassword = Get-PasswordDialog

if ([string]::IsNullOrWhiteSpace($plainPassword)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Password is required to configure the ODBC connection.",
        "ILLiad ODBC Setup - Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}

# Detect Office
$officeArch = (Get-ItemProperty "HKLM:\Software\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue).Platform
$platform = if ($officeArch -eq "x64") { "64-bit" } else { "32-bit" }
$driverPath = if ($platform -eq "64-bit") { "C:\Windows\System32\sqlncli11.dll" } else { "C:\Windows\SysWOW64\sqlncli11.dll" }

# Verify SQL Server Native Client driver exists
if (-not (Test-Path $driverPath)) {
    $errorMessage = @"
SQL Server Native Client 11.0 driver not found.

Detected Office: $platform
Expected location: $driverPath

To install SQL Server Native Client 11.0:
1. Download from Microsoft:
   https://www.microsoft.com/en-us/download/details.aspx?id=50402
2. Install the version matching your Office architecture
3. Run this setup again

"@
    [System.Windows.Forms.MessageBox]::Show(
        $errorMessage,
        "ILLiad ODBC Setup - Missing Driver",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}

# Remove old DSN configurations
Remove-OdbcDsn -Name $dsnName -DsnType User -Platform $platform -ErrorAction SilentlyContinue

# Create registry paths for User DSN
$regPath = "HKCU:\SOFTWARE\ODBC\ODBC.INI\$dsnName"
$regListPath = "HKCU:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources"

try {
    $null = New-Item -Path "HKCU:\SOFTWARE\ODBC\ODBC.INI" -Force -ErrorAction SilentlyContinue
    $null = New-Item -Path $regListPath -Force -ErrorAction SilentlyContinue
    $null = New-Item -Path $regPath -Force -ErrorAction Stop
} catch {
    $errorMessage = @"
Failed to create registry entries for ODBC configuration.

Error: $($_.Exception.Message)

This may indicate a permissions issue or registry corruption.
"@
    [System.Windows.Forms.MessageBox]::Show(
        $errorMessage,
        "ILLiad ODBC Setup - Registry Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
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
    $errorMessage = @"
Failed to configure ODBC settings in the registry.

Error: $($_.Exception.Message)

The configuration could not be completed.
"@
    [System.Windows.Forms.MessageBox]::Show(
        $errorMessage,
        "ILLiad ODBC Setup - Configuration Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )

    # Clean up password before exit
    $plainPassword = $null
    [System.GC]::Collect()

    exit 1
}

$plainPassword = $null
[System.GC]::Collect()

# Show success message
$successMessage = @"
ILLiad ODBC connection configured successfully!

DSN Name: $dsnName
Server: $serverName
Database: $database

You can now use this connection in Microsoft Access.
Access the database at:
G:\Shared drives\Resource Sharing & Reserves\ILL

Note: First connection may take 20-30 seconds.

Security Reminder: Password is stored in your user registry (HKCU).
"@

[System.Windows.Forms.MessageBox]::Show(
    $successMessage,
    "ILLiad ODBC Setup - Complete",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
)

exit 0