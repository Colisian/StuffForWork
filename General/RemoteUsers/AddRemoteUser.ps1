# Load Windows Forms assembly
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create and configure the form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Enter Directory Shortname"
$form.Size = New-Object System.Drawing.Size(400,150)
$form.StartPosition = "CenterScreen"

# Create a label for instructions
$label = New-Object System.Windows.Forms.Label
$label.Text = "Enter your directory shortname:"
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(10,20)
$form.Controls.Add($label)

#Create a textbox for user input
$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Location = New-Object System.Drawing.Point(10,50)
$textBox.Width = 360
$form.Controls.Add($textBox)

#Create an OK button to submit input
$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Location = New-Object System.Drawing.Point(290,80)
$okButton.Add_Click({
    # Store the textbox input in the form's Tag property
    $form.Tag = $textBox.Text
    $form.Close()
})
$form.Controls.Add($okButton)

# Show the form as a modal dialog
$form.ShowDialog() | Out-Null

#Retrieve the entered directory
$userShortName = $form.Tag

#Check if the user provided any input
if ([string]::IsNullOrEmpty($userShortName)) {
    Write-Host "No input provided. Exiting."
    exit 1
}

# Construct the AzureAD account name
$azureUser = "$userShortName"
Write-Host "Attempting to add $azureUser to the Remote Desktop Users group..."

# Get the Remote Desktop Users group object using ADSI
$remoteDesktopGroup = [ADSI]"WinNT://$env:COMPUTERNAME/Remote Desktop Users,group"

# Attempt to add the specified AzureAD user to the group
try {
    Add-LocalGroupMember -Group "Remote Desktop Users" -Member $azureUser
    Write-Host "Successfully added $azureUser to the Remote Desktop Users group." -ForegroundColor Green
} catch {
    Write-Host "Error adding $azureUser $_" -ForegroundColor Red
    exit 1
}
