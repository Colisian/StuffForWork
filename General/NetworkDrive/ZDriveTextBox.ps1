# Function to show input popup
function Show-InputBox {
    param (
        [string]$Message,
        [string]$Title
    )

    # Load WPF assemblies
    Add-Type -AssemblyName PresentationFramework

    # Create the input dialog
    $Window = New-Object System.Windows.Window
    $Window.Title = $Title
    $Window.Width = 400
    $Window.Height = 200
    $Window.WindowStartupLocation = 'CenterScreen'
    $Window.ResizeMode = 'NoResize'

    # Create a grid layout
    $Grid = New-Object System.Windows.Controls.Grid
    $Grid.Margin = "10"

    # Add a text block for the message
    $TextBlock = New-Object System.Windows.Controls.TextBlock
    $TextBlock.Text = $Message
    $TextBlock.Margin = "0,0,0,10"
    $TextBlock.HorizontalAlignment = "Left"
    $Grid.Children.Add($TextBlock)

    # Add a text box for input
    $TextBox = New-Object System.Windows.Controls.TextBox
    $TextBox.Margin = "0,40,0,10"
    $TextBox.VerticalAlignment = "Center"
    $TextBox.HorizontalAlignment = "Stretch"
    $Grid.Children.Add($TextBox)

    # Add a button for submission
    $Button = New-Object System.Windows.Controls.Button
    $Button.Content = "Submit"
    $Button.Width = 100
    $Button.HorizontalAlignment = "Right"
    $Button.VerticalAlignment = "Bottom"
    $Button.Margin = "0,100,10,0"
    $Button.IsDefault = $true
    $Grid.Children.Add($Button)

    # Handle the button click
    $Button.Add_Click({
        $Window.DialogResult = $true
        $Window.Close()
    })

    # Set window content and show the dialog
    $Window.Content = $Grid
    if ($Window.ShowDialog() -eq $true) {
        return $TextBox.Text
    } else {
        return $null
    }
}
    

# Display the popup for user input
$UserInput = Show-InputBox -Message "Enter UMD Directory IDs separated by commas (e.g., user1,user2,user3):" -Title "Enter Directory IDs"

if ($UserInput -ne $null -and $UserInput -ne "") {

    # Ensure $UserInput is treated as a string and split into an array if needed
    $UserIDs = ($UserInput -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

    # Filter out any purely numerical inputs
    $UserIDs = $UserIDs | Where-Object { $_ -notmatch '^\d+$' }

    # Debug: Show the processed UserIDs array
    Write-Host "Filtered User IDs: $($UserIDs -join ', ')" -ForegroundColor Green

    # Base Path and other settings
    $BasePath = "H:\userhome"
    $Domain = "AD"
    $LogFile = "C:\ZDriveSetupLog.txt"

    Start-Transcript -Path $LogFile -Append

    # Function to Create Z Drive Folder and Set Permissions
    function Create-ZDriveFolder { 
        param (
            [string]$UserID
        )

        # Construct the folder path correctly
        $UserFolder = Join-Path -Path $BasePath -ChildPath $UserID

        # Step 1: Create Folder
        try {
            if (-not (Test-Path -Path $UserFolder)) {
                New-Item -Path $UserFolder -ItemType Directory | Out-Null
                Write-Host "Folder created: $UserFolder" -ForegroundColor Green
            } else {
                Write-Host "Folder already exists: $UserFolder" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Error creating folder for user: $UserID. Error: $_" -ForegroundColor Red
        }

        # Step 2: Set Permissions
        try {
            $Acl = Get-Acl -Path $UserFolder
            $User = "$Domain\$UserID"

            # Grant Full Control to the User
            $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($User, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
            $Acl.AddAccessRule($AccessRule)

            # Disable Inheritance and Convert to Explicit Permissions
            $Acl.SetAccessRuleProtection($true, $true)

            # Apply Permissions
            Set-Acl -Path $UserFolder -AclObject $Acl

            Write-Host "Permissions set successfully for user: $UserID" -ForegroundColor Green
        } catch {
            Write-Host "Error setting permissions for user: $UserID. Error: $_" -ForegroundColor Red
        }
    }

    # Loop through each user and perform the setup
    foreach ($UserID in $UserIDs) {
        if ($UserID -ne "") {
            Write-Host "Processing user: $UserID..." -ForegroundColor Cyan
            Create-ZDriveFolder -UserID $UserID
        } else {
            Write-Host "Skipping empty input..." -ForegroundColor Yellow
        }
    }

    # Stop logging
    Stop-Transcript

    Write-Host "Z Drive setup completed for all users. Check the log file at $LogFile for details." -ForegroundColor Green
} else {
    Write-Host "No valid input provided. Exiting..." -ForegroundColor Red
}

