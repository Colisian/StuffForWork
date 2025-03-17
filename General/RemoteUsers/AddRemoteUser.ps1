#Load Windows forms assembly
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#Create and configure form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Add Remote User Name"
$form.Size = New-Object System.Drawing.Size(400,150)
$form.StartPosition = "CenterScreen"

#Create and configure label
$label = New-Object System.Windows.Forms.Label
$label.Text = "Enter your directory name:"
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(10,20)
$form.Controls.Add($label)

#Create and configure text box
$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Location = New-Object System.Drawing.Point(10,40)
$textBox.Width = 360
$form.Controls.Add($textBox)

#Create and configure OK button
$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Location = New-Object System.Drawing.Point(290,80)
$okButton.Add_Click({
    $form.Tag = $textBox.Text
    $form.Close()
})
$form.Controls.Add($okButton)

#Show the form as a dialog
$form.ShowDialog | Out-Null

#Get the user name from the form
$userShortName = $form.Tag

#Check if input
if ([string]:: ::IsNullOrEmpty($userShortName)) {
    Write-Host "No user name entered. Exiting script."
    exit 1
}

#AzureAd account
$azureAdUser = "AzureAD\$userShortName"
Write-Host "Adding user '$azureAdUser' to the Remote Desktop Users group."

#Get remote Desktop users Group
$remoteDesktopGroup = [ADSI]"WinNT://$env:COMPUTERNAME/Remote Desktop Users,group"

#Add user to the group
try{
    $remoteDesktopGroup.Add("WinNT://$azureADUser")
    Write-Host "User '$azureAdUser' added to the Remote Desktop Users group."
} catch {
    Write-Host "Failed to add user '$azureAdUser' to the Remote Desktop Users group."
    exit 1
}