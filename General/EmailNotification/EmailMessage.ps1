
#variables
$thresholdGB = 200
$threshold = $thresholdGB * 1GB
$disk = Get-PSDrive -Name "C"  


#Email Variables
$EmailTo = "cmcleod1@umd.edu"
$EmailFrom = "cmcleod1@umd.edu"
$SMTPServer = "smtp.gmail.com"
$SMTPPort = 587
$Username = "cmcleod1@umd.edu"
$Password =  # This is the 16-character app password generated 

#Funaction to send an email using Gmail SMTP server

Function Send-Email {
param (
    [Parameter(Mandatory=$true)][string]$To,
    [Parameter(Mandatory=$true)][string]$From,
    [Parameter(Mandatory=$true)][string]$Body,
    [Parameter(Mandatory=$true)][string]$Subject,
    [Parameter(Mandatory=$true)][string]$SMTPServer,
    [Parameter(Mandatory=$true)][string]$SMTPPort,
    [Parameter(Mandatory=$true)][string]$Username,
    [Parameter(Mandatory=$true)][string]$Password

)
#Create a secure password
$SecurePassword = $Password | ConvertTo-SecureString -AsPlainText -Force

#Create a PSCredential object
$SMTPCredential = New-Object System.Management.Automation.PSCredential ($Username, $SecurePassword)

#Create a hashtable for the email message
$MailMessage = @{
    To = $To
    From = $From
    Subject = $Subject
    Body = $Body
    SmtpServer = $SMTPServer
    Port = $SMTPPort
    UseSsl = $true
    Credential = $SMTPCredential
}

Send-MailMessage @MailMessage
}
# Check if free space is below the threshold
if ($disk.Free -lt $threshold) {
    $freeSpaceGB = [math]::Round($disk.Free / 1GB, 2)
    $thresholdGB = [math]::Round($threshold / 1GB, 2)

    $bodyText = "Warning: The drive $($disk.Name) on $($env:COMPUTERNAME) is running low on disk space. Free space: $freeSpaceGB GB of threshold: $thresholdGB GB."
    $subjectText = "Low Disk Space Alert on $($env:COMPUTERNAME)"

    # Sending the email
    Send-Email -To $emailTo -From $emailFrom -Body $bodyText -Subject $subjectText -SMTPServer $smtpServer -SMTPPort $smtpPort -Username $username -Password $Password
    Write-Host "Email sent successfully!"
} else {
    Write-Host "Disk space is above the threshold. No email sent."
    Write-Host "Free space: $freeSpaceGB ."
}